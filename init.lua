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
require("config.cheatsheet").setup()
require("config.autocmds")
require("config.dashboard").setup()
require("config.statusline").setup()
require("config.lazy")
