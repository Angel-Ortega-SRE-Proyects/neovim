local opt = vim.opt

-- UI
opt.number = true
opt.relativenumber = false -- fija (1,2,3...), no salta al moverte
opt.cursorline = true
opt.signcolumn = "yes"
opt.termguicolors = true
opt.scrolloff = 8
opt.splitright = true
opt.splitbelow = true
opt.wrap = false
opt.laststatus = 3 -- una sola barra de estado global (lualine.globalstatus)

-- Indentation
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.softtabstop = 2
opt.smartindent = true

-- Search
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

-- Files
-- Permite una configuración opcional por proyecto en `<raíz>/.nvim.lua`.
-- `secure` mantiene restringidas las órdenes sensibles en esos archivos.
opt.exrc = true
opt.secure = true
local state_dir = vim.fn.stdpath("state")
local undo_dir = state_dir .. "/undo"
local swap_dir = state_dir .. "/swap"
vim.fn.mkdir(undo_dir, "p")
vim.fn.mkdir(swap_dir, "p")

opt.hidden = true -- conserva cambios al cambiar de buffer hasta guardarlos
opt.swapfile = true
opt.backup = false
opt.writebackup = true
opt.undofile = true
opt.undodir = undo_dir .. "//"
opt.directory = swap_dir .. "//"

-- Behavior
opt.updatetime = 500
opt.timeoutlen = 300
opt.clipboard = "unnamedplus"
opt.mouse = "a"
opt.completeopt = { "menu", "menuone", "noselect" }
opt.wildmode = "full"
opt.wildoptions = "pum"
