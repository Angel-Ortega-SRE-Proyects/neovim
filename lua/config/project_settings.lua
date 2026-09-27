-- Contexto común para configuraciones específicas de cada proyecto.
-- Neovim carga automáticamente `<cwd>/.nvim.lua` cuando `exrc` está activo;
-- este módulo mantiene disponible la raíz actual y notifica el cambio.
local M = {}

function M.refresh()
  local root = vim.fn.getcwd()
  vim.g.project_root = root
  vim.api.nvim_exec_autocmds("User", {
    pattern = "ProjectChanged",
    data = { root = root },
    modeline = false,
  })
end

function M.setup()
  local group = vim.api.nvim_create_augroup("ProjectSettings", { clear = true })
  vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged", "TabEnter" }, {
    group = group,
    callback = M.refresh,
    desc = "Actualizar contexto de configuración del proyecto",
  })
end

return M
