local M = {}

local function valid_buffer(buf)
  return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end

local function reload_ai_cli()
  local reopen = false
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    local ok, is_agent_hub = pcall(vim.api.nvim_tabpage_get_var, tabpage, "agent_hub")
    if ok and is_agent_hub then
      reopen = true
      break
    end
  end

  if vim.fn.exists(":AgentHubClose") == 2 then
    pcall(vim.cmd, "AgentHubClose")
  end

  for _, command in ipairs({
    "Claude", "Codex", "OpenCode", "Gemini", "CopilotCli", "Grok", "Agents",
    "AgentWorkspace", "AgentDiff", "AgentKill", "AgentsKillAll", "AgentHubClose",
  }) do
    pcall(vim.api.nvim_del_user_command, command)
  end

  package.loaded["plugins.ai_cli"] = nil
  local ok, err = pcall(require, "plugins.ai_cli")
  if not ok then
    vim.notify("No se pudo recargar Agent Hub: " .. err, vim.log.levels.ERROR)
    return
  end

  if reopen then
    pcall(vim.cmd, "Agents")
  end
end

local function open_commit_for_buffer(buf)
  local file_lines = vim.b[buf].agent_hub_changed_files
  local candidate = type(file_lines) == "table" and file_lines[vim.fn.line(".")] or nil
  local root = type(candidate) == "table" and type(candidate.root) == "string"
      and candidate.root or vim.fn.getcwd()
  require("config.git_commit").open(root, nil, vim.api.nvim_get_current_win())
end

local function center_welcome_buffer(buf, win)
  if not (valid_buffer(buf) and type(win) == "number" and vim.api.nvim_win_is_valid(win)) then return end
  local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local first = 1
  while first <= #current and current[first] == "" do first = first + 1 end
  local last = #current
  while last >= first and current[last] == "" do last = last - 1 end
  if first > last then return end

  local content = vim.list_slice(current, first, last)
  local height = vim.api.nvim_win_get_height(win)
  local top_padding = math.max(0, math.floor((height - #content) / 2))
  local lines = {}
  for _ = 1, top_padding do lines[#lines + 1] = "" end
  vim.list_extend(lines, content)
  for _ = 1, top_padding do lines[#lines + 1] = "" end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function find_welcome_window(tabpage)
  if type(tabpage) ~= "number" or not vim.api.nvim_tabpage_is_valid(tabpage) then return end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.api.nvim_win_get_height(win) > 5
        and (name == "" or name:match("Agent Hub Welcome "))
        and vim.bo[buf].buftype == "nofile" then
      return buf, win
    end
  end
end

local function name_hub_buffers(tabpage)
  if type(tabpage) ~= "number" or not vim.api.nvim_tabpage_is_valid(tabpage) then return end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if valid_buffer(buf) and vim.api.nvim_buf_get_name(buf) == ""
        and vim.bo[buf].buftype == "nofile" then
      local label = vim.api.nvim_win_get_height(win) > 5 and "Agent Hub Welcome " or "Agent Hub Actions "
      vim.api.nvim_buf_set_name(buf, label .. buf)
    end
  end
end

local function restore_hub_navigation(tabpage)
  if type(tabpage) ~= "number" or not vim.api.nvim_tabpage_is_valid(tabpage) then return end
  local directions = {
    ["<C-Left>"] = "h",
    ["<C-Right>"] = "l",
    ["<C-Up>"] = "k",
    ["<C-Down>"] = "j",
    ["<leader>a<Left>"] = "h",
    ["<leader>a<Right>"] = "l",
    ["<leader>a<Up>"] = "k",
    ["<leader>a<Down>"] = "j",
  }
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if valid_buffer(buf) then
      for key, direction in pairs(directions) do
        vim.keymap.set({ "n", "t" }, key, function()
          vim.cmd("wincmd " .. direction)
        end, { buffer = buf, desc = "AgentHub: ir al panel", nowait = true, silent = true })
      end
    end
  end
end

function M.apply()
  reload_ai_cli()

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if valid_buffer(buf) and vim.bo[buf].filetype == "gitcommit" then
      vim.bo[buf].buflisted = true
    end
    if valid_buffer(buf) and vim.api.nvim_buf_get_name(buf):match("Agent Changes") then
      vim.keymap.set("n", "c", function()
        if not valid_buffer(buf) then return end
        open_commit_for_buffer(buf)
      end, { buffer = buf, desc = "Crear commit con Copilot", nowait = true, silent = true })
    end
  end

  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    local ok, is_agent_hub = pcall(vim.api.nvim_tabpage_get_var, tabpage, "agent_hub")
    if ok and is_agent_hub then
      name_hub_buffers(tabpage)
      restore_hub_navigation(tabpage)
      local buf, win = find_welcome_window(tabpage)
      if buf and win then center_welcome_buffer(buf, win) end
    end
  end

  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("AgentHubHotReloadCentering", { clear = true }),
    callback = function()
      for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
        local ok, is_agent_hub = pcall(vim.api.nvim_tabpage_get_var, tabpage, "agent_hub")
        if ok and is_agent_hub then
          local buf, win = find_welcome_window(tabpage)
          if buf and win then center_welcome_buffer(buf, win) end
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinResized", {
    group = vim.api.nvim_create_augroup("AgentHubHotReloadWinCentering", { clear = true }),
    callback = function()
      for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
        local ok, is_agent_hub = pcall(vim.api.nvim_tabpage_get_var, tabpage, "agent_hub")
        if ok and is_agent_hub then
          local buf, win = find_welcome_window(tabpage)
          if buf and win then center_welcome_buffer(buf, win) end
        end
      end
    end,
  })
end

return M
