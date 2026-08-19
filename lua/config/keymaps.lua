local map = vim.keymap.set

-- Window navigation
map("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })

-- Buffers
map("n", "<S-h>", ":bprevious<CR>", { desc = "Prev buffer" })
map("n", "<S-l>", ":bnext<CR>", { desc = "Next buffer" })
map("n", "<leader>bd", ":bdelete<CR>", { desc = "Delete buffer" })

-- Editing
map("n", "<Esc>", ":nohlsearch<CR>", { desc = "Clear search highlight" })
map("v", "<", "<gv", { desc = "Indent left" })
map("v", ">", ">gv", { desc = "Indent right" })
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- File explorer / search (placeholders for plugin keymaps set in lua/plugins)
map("n", "<leader>w", ":w<CR>", { desc = "Save file" })
map("n", "<leader>q", ":q<CR>", { desc = "Quit" })

-- Mismo resultado que "!" (filtrar por un comando externo), pero sin
-- necesitar visual+! o normal+!+motion: abre directo la cmdline ":!" con el
-- ícono de terminal (ver lua/plugins/noice.lua).
map("n", "<leader>!", ":.!", { desc = "Filtrar línea actual por comando externo" })
map("v", "<leader>!", ":!", { desc = "Filtrar selección por comando externo" })
