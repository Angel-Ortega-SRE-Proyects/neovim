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

function M.start_watch()
  refresh_branch()
  local timer = vim.uv.new_timer()
  timer:start(
    1000,
    5000,
    vim.schedule_wrap(refresh_branch)
  )
  vim.api.nvim_create_autocmd("DirChanged", {
    group = vim.api.nvim_create_augroup("GitBranchWatch", { clear = true }),
    callback = refresh_branch,
  })
end

return M
