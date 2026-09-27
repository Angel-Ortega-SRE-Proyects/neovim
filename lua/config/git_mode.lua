local M = {}

local mode = {}
local render
local git_namespace = vim.api.nvim_create_namespace("git-hub")

local function valid_buffer(buf)
  return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end

local function valid_window(win)
  return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

local function notify_repo_required()
  vim.notify("No estás dentro de un repositorio Git (" .. vim.fn.getcwd() .. ")", vim.log.levels.WARN)
end

local function in_repo()
  vim.fn.system("git rev-parse --is-inside-work-tree")
  return vim.v.shell_error == 0
end

local function run_if_repo(action)
  if in_repo() then action() else notify_repo_required() end
end

local function load_git_plugins()
  local ok, lazy = pcall(require, "lazy")
  if ok then
    lazy.load({ plugins = { "telescope.nvim", "diffview.nvim", "gitsigns.nvim" } })
  end
end

local function close()
  if type(mode.tabpage) == "number" and vim.api.nvim_tabpage_is_valid(mode.tabpage) then
    vim.api.nvim_set_current_tabpage(mode.tabpage)
    vim.cmd("tabclose")
  end
  mode = {}
end

local function recover_mode_tab()
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    local ok, is_git_hub = pcall(vim.api.nvim_tabpage_get_var, tabpage, "git_hub")
    if ok and is_git_hub then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if valid_buffer(buf) and vim.api.nvim_buf_get_name(buf):match("Git Hub$") then
          mode.tabpage = tabpage
          mode.buf = buf
          mode.win = win
          return true
        end
      end
    end
  end
  return false
end

function M.back()
  local ok, actions = pcall(require, "telescope.actions")
  if ok then pcall(actions.close, vim.api.nvim_get_current_buf()) end
  pcall(vim.cmd, "DiffviewClose")
  if type(mode.tabpage) == "number" and vim.api.nvim_tabpage_is_valid(mode.tabpage) then
    vim.api.nvim_set_current_tabpage(mode.tabpage)
    if valid_window(mode.win) then
      vim.api.nvim_set_current_win(mode.win)
      render(mode.buf)
    else
      vim.cmd("tabclose")
      mode = {}
      M.open()
    end
  else
    M.open()
  end
end

local function actions()
  local git = require("config.git")
  return {
    { "󰊢  Historial de commits", function() run_if_repo(git.open_commits) end },
    { "  Ramas y checkout       <C-o>", function() run_if_repo(git.guard("Telescope git_branches")) end },
    { "󰙅  Estado y cambios", function() run_if_repo(git.open_status) end },
    { "󰕯  Diff de cambios", function() run_if_repo(git.guard("DiffviewOpen")) end },
    { "󰋚  Historial del repositorio", function() run_if_repo(git.guard("DiffviewFileHistory")) end },
    { "󰐕  Stage del archivo actual", function() run_if_repo(function() require("gitsigns").stage_buffer() end) end },
    { "󰜘  Crear commit con Copilot", function()
      run_if_repo(function()
        require("config.git_commit").open(vim.fn.getcwd(), function() M.open(true) end)
      end)
    end },
    { "󰑐  Actualizar Git Hub", function() M.open(true) end },
    { "󰅖  Cerrar Git Hub", close },
  }
end

render = function(buf)
  if not valid_buffer(buf) then
    if mode.buf == buf then mode.buf = nil end
    return false
  end
  local lines = {
    "   GIT HUB  ·  CONTROL DE REPOSITORIO",
    "   ─────────────────────────────────────────",
    "",
    "     " .. vim.fn.getcwd(),
    "",
    "   ACCIONES",
    "   ─────────",
    "",
  }
  for index, action in ipairs(actions()) do
    lines[#lines + 1] = string.format(" %d  %s", index, action[1])
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = ""
  lines[#lines + 1] = "   Enter ejecutar   ·   r actualizar   ·   q cerrar"
  lines[#lines + 1] = "   Esc / :GitBack volver al menú desde cualquier vista"
  vim.bo[buf].modifiable = true
  local ok, err = pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  if not ok then
    vim.notify("No se pudo renderizar Git Hub: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  vim.api.nvim_buf_clear_namespace(buf, git_namespace, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, git_namespace, "Title", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, git_namespace, "Directory", 3, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, git_namespace, "Comment", 5, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, git_namespace, "Comment", 7 + #actions(), 0, -1)
  return true
end

local function execute_selected(buf)
  local action = actions()[vim.fn.line(".") - 8]
  if action then action[2]() end
end

local function create_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].filetype = "git-mode"
  vim.api.nvim_buf_set_name(buf, "Git Hub")
  vim.keymap.set("n", "<CR>", function() execute_selected(buf) end,
    { buffer = buf, desc = "Ejecutar acción Git" })
  vim.keymap.set("n", "q", close, { buffer = buf, desc = "Cerrar Git Hub" })
  vim.keymap.set("n", "<Esc>", M.back, { buffer = buf, desc = "Volver al menú Git" })
  vim.keymap.set("n", "r", function() render(buf) end,
    { buffer = buf, desc = "Actualizar modo Git" })
  return buf
end

function M.open(refresh)
  if not in_repo() then
    notify_repo_required()
    return
  end
  load_git_plugins()
  if not (mode.tabpage and vim.api.nvim_tabpage_is_valid(mode.tabpage)) then
    recover_mode_tab()
  end
  if mode.tabpage and vim.api.nvim_tabpage_is_valid(mode.tabpage) then
    vim.api.nvim_set_current_tabpage(mode.tabpage)
    if not (valid_window(mode.win)
        and valid_buffer(mode.buf)
        and vim.api.nvim_win_get_buf(mode.win) == mode.buf) then
      vim.cmd("tabclose")
      mode = {}
    else
      vim.api.nvim_set_current_win(mode.win)
      if refresh then render(mode.buf) end
      return
    end
  end
  vim.cmd("tabnew")
  mode.tabpage = vim.api.nvim_get_current_tabpage()
  vim.api.nvim_tabpage_set_var(mode.tabpage, "git_hub", true)
  mode.buf = create_buffer()
  local width = math.min(86, math.max(62, vim.o.columns - 8))
  local height = math.min(22, math.max(14, #actions() + 11))
  mode.win = vim.api.nvim_open_win(mode.buf, true, {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Git Hub ",
    title_pos = "center",
  })
  vim.wo[mode.win].cursorline = true
  vim.wo[mode.win].winhl = "Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:CursorLine"
  if not render(mode.buf) or not valid_window(mode.win) then
    mode = {}
    vim.notify("No se pudo abrir Git Hub: ventana inválida", vim.log.levels.ERROR)
    return
  end
  local last_line = vim.api.nvim_buf_line_count(mode.buf)
  pcall(vim.api.nvim_win_set_cursor, mode.win, { math.min(9, last_line), 0 })
end

function M.open_copilot()
  vim.cmd("CopilotCli")
end

function M.setup_keymaps()
  for _, key in ipairs({ "<leader>g", "<leader>gb", "<leader>gc", "<leader>gs", "<leader>gd", "<leader>gh" }) do
    pcall(vim.keymap.del, "n", key)
  end
  vim.keymap.set("n", "<leader>gg", M.open, { desc = "Abrir modo Git" })
  vim.keymap.set("n", "<leader>gc", M.open_copilot, { desc = "Abrir GitHub Copilot" })
  vim.api.nvim_create_user_command("GitBack", M.back,
    { desc = "Volver al menú Git", force = true })
end

return M
