local map = vim.keymap.set

-- Window navigation: ver lua/plugins/smart-splits.lua (C-Flechas cruza también
-- hacia panes de tmux, no solo splits de Neovim).

-- Buffers
map("n", "<S-h>", ":bprevious<CR>", { desc = "Prev buffer" })
map("n", "<S-l>", ":bnext<CR>", { desc = "Next buffer" })

-- Editing
map("n", "<Esc>", ":nohlsearch<CR>", { desc = "Clear search highlight" })
map("n", "<leader>uc", "<cmd>ThemeSelect<CR>", { desc = "Cambiar tema de colores" })
map("c", "<Down>", function()
  return vim.fn.wildmenumode() == 1 and "<C-n>" or "<Down>"
end, { expr = true, replace_keycodes = true, desc = "Siguiente sugerencia de comando" })
map("c", "<Up>", function()
  return vim.fn.wildmenumode() == 1 and "<C-p>" or "<Up>"
end, { expr = true, replace_keycodes = true, desc = "Sugerencia anterior de comando" })
map("c", "<Esc>", function()
  return vim.fn.wildmenumode() == 1 and "<C-e>" or "<Esc>"
end, { expr = true, replace_keycodes = true, desc = "Cerrar sugerencias o salir del comando" })
map("v", "<", "<gv", { desc = "Indent left" })
map("v", ">", ">gv", { desc = "Indent right" })
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- File explorer / search (placeholders for plugin keymaps set in lua/plugins)
map("n", "<C-s>", ":update<CR>", { desc = "Guardar cambios" })
map("i", "<C-s>", "<C-o>:update<CR>", { desc = "Guardar cambios" })
