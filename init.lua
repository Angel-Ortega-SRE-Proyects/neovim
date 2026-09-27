vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Vim intenta "navegar" dentro de .zip/.jar/.odt/.ods/.xlsx (son zips por
-- dentro) como si fueran texto, mezclando el listado del archivo con
-- contenido roto. Se desactiva esa navegación nativa; ver
-- lua/config/autocmds.lua para que en su lugar se abran con la app del
-- sistema.
vim.g.loaded_zipPlugin = 1
vim.g.loaded_tarPlugin = 1

require("config.options")
require("config.keymaps")
require("config.project_settings").setup()
require("config.buffers").setup()
require("config.autocmds")
require("config.theme")
require("config.dashboard").setup()
require("config.statusline").setup()
require("config.topline").setup()
require("config.lazy")

vim.api.nvim_create_user_command("ConfigReload", function()
  local config_file = vim.fn.stdpath("config") .. "/init.lua"
  vim.cmd("source " .. vim.fn.fnameescape(config_file))
  vim.api.nvim_echo({
    { "Configuración recargada: ", "Normal" },
    { config_file, "String" },
  }, false, {})
end, {
  desc = "Recargar la configuración de Neovim",
  force = true,
})
