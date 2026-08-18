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

return M
