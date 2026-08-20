local map = vim.keymap.set

-- Window navigation: ver lua/plugins/smart-splits.lua (C-hjkl cruza también
-- hacia panes de tmux, no solo splits de Neovim).

-- Splits, mismos atajos que ~/.tmux.conf (prefix ahí es C-z, acá <leader>):
--   . -> split lado a lado, - -> split arriba/abajo, x -> cerrar, z -> zoom
map("n", "<leader>.", ":vsplit<CR>", { desc = "Split lado a lado" })
map("n", "<leader>-", ":split<CR>", { desc = "Split arriba/abajo" })
map("n", "<leader>x", "<C-w>c", { desc = "Cerrar split actual" })

local zoomed = false
map("n", "<leader>z", function()
  if zoomed then
    vim.cmd("wincmd =")
  else
    vim.cmd("wincmd |")
    vim.cmd("wincmd _")
  end
  zoomed = not zoomed
end, { desc = "Zoom split actual (toggle)" })

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
