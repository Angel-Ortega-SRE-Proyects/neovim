-- Helper compartido para comandos de git: evita el traceback feo de
-- Telescope/Diffview cuando el cwd actual no es un repositorio git.
local M = {}

function M.in_repo()
  vim.fn.system("git rev-parse --is-inside-work-tree")
  return vim.v.shell_error == 0
end

--- Envuelve un comando `:cmd` para que solo se ejecute dentro de un repo git.
function M.guard(cmd)
  return function()
    if M.in_repo() then
      vim.cmd(cmd)
    else
      vim.notify("No estás dentro de un repositorio git (" .. vim.fn.getcwd() .. ")", vim.log.levels.WARN)
    end
  end
end

-- Rama actual, cacheada y refrescada sola (no depende de tener un buffer de
-- archivo enfocado, por eso funciona también parado en el explorador o en
-- el dashboard). La usa lua/config/statusline.lua.
local branch = ""

local function refresh_branch()
  local cwd = vim.fn.getcwd()
  vim.system({ "git", "branch", "--show-current" }, { text = true, cwd = cwd }, function(res)
    branch = (res.code == 0 and res.stdout) and vim.trim(res.stdout) or ""
  end)
end

function M.branch()
  return branch
end

-- Cambios SIN commitear en la rama actual (staged + sin stage, contra
-- HEAD) -- { files, add, del } o nil si está todo limpio / no hay HEAD
-- todavía (repo sin commits). --numstat en vez de --shortstat: el texto de
-- --shortstat viene en el idioma de git (locale), --numstat es siempre
-- números en columnas fijas, no depende de eso. La usa lua/plugins/editor.lua
-- (bufferline) para la barra de arriba.
local diff_stat = nil

local function map_picker_return(prompt_bufnr, map)
  local actions = require("telescope.actions")
  local function return_to_git_hub()
    actions.close(prompt_bufnr)
    vim.schedule(function()
      local ok, git_mode = pcall(require, "config.git_mode")
      if ok then git_mode.back() end
    end)
  end
  map("i", "<Esc>", return_to_git_hub)
  map("n", "q", return_to_git_hub)
end

local function refresh_diff_stat()
  local cwd = vim.fn.getcwd()
  vim.system({ "git", "diff", "--numstat", "HEAD" }, { text = true, cwd = cwd }, function(res)
    if res.code ~= 0 or not res.stdout or vim.trim(res.stdout) == "" then
      diff_stat = nil
      return
    end
    local files, add, del = 0, 0, 0
    for line in res.stdout:gmatch("[^\n]+") do
      files = files + 1
      local a, d = line:match("^(%d+)%s+(%d+)%s+")
      if a then
        add = add + tonumber(a)
        del = del + tonumber(d)
      end
      -- binarios: "-\t-\tpath" -- ya se contó el archivo, no suman líneas
    end
    diff_stat = { files = files, add = add, del = del }
  end)
end

function M.diff_stat()
  return diff_stat
end

--- Picker de commits donde <CR> abre el diff de ese commit en Diffview
--- (en vez del `checkout` que Telescope hace por defecto, que muta el
--- working tree sin avisar). <C-o> conserva el checkout por si hace falta.
function M.open_commits()
  if not M.in_repo() then
    vim.notify("No estás dentro de un repositorio git (" .. vim.fn.getcwd() .. ")", vim.log.levels.WARN)
    return
  end
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  require("telescope.builtin").git_commits({
    attach_mappings = function(prompt_bufnr, map)
      local function view_diff()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        vim.cmd("DiffviewOpen " .. entry.value .. "^!")
      end
      map("i", "<CR>", view_diff)
      map("n", "<CR>", view_diff)
      map("i", "<C-o>", actions.git_checkout)
      map("n", "<C-o>", actions.git_checkout)
      map_picker_return(prompt_bufnr, map)
      return true
    end,
  })
end

--- Picker de status donde <CR> abre el archivo completo en Diffview (líneas
--- modificadas marcadas en el gutter, igual que el resto de pickers de git).
--- <C-e> conserva el open plano de Telescope por si solo quieres editar.
function M.open_status()
  if not M.in_repo() then
    vim.notify("No estás dentro de un repositorio git (" .. vim.fn.getcwd() .. ")", vim.log.levels.WARN)
    return
  end
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  require("telescope.builtin").git_status({
    attach_mappings = function(prompt_bufnr, map)
      local function view_diff()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        vim.cmd("DiffviewOpen -- " .. entry.value)
      end
      map("i", "<CR>", view_diff)
      map("n", "<CR>", view_diff)
      map("i", "<C-e>", actions.select_default)
      map("n", "<C-e>", actions.select_default)
      map_picker_return(prompt_bufnr, map)
      return true
    end,
  })
end

local function refresh_all()
  refresh_branch()
  refresh_diff_stat()
end

function M.start_watch()
  refresh_all()
  local timer = vim.uv.new_timer()
  timer:start(
    1000,
    5000,
    vim.schedule_wrap(refresh_all)
  )
  vim.api.nvim_create_autocmd("DirChanged", {
    group = vim.api.nvim_create_augroup("GitBranchWatch", { clear = true }),
    callback = refresh_all,
  })
  -- Guardar un archivo es el momento más común en que cambia el diff --
  -- no hace falta esperar hasta el próximo tick del timer (hasta 5s).
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("GitDiffStatWatch", { clear = true }),
    callback = refresh_diff_stat,
  })
end

return M
