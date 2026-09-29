-- Entorno mínimo para la suite (plenary/busted). tests/run.sh exporta
-- NVIM_TEST_PLUGINS con la carpeta real de plugins de lazy.nvim, porque
-- HOME y XDG_* apuntan a directorios temporales durante las pruebas.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local plugins = vim.env.NVIM_TEST_PLUGINS or vim.fn.expand("~/.local/share/nvim/lazy")

vim.opt.rtp:prepend(root)
for _, plugin in ipairs({ "plenary.nvim", "telescope.nvim", "tokyonight.nvim", "nvim-web-devicons" }) do
  local path = plugins .. "/" .. plugin
  if vim.fn.isdirectory(path) == 1 then
    vim.opt.rtp:append(path)
  end
end

vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.o.swapfile = false
package.path = root .. "/?.lua;" .. package.path
