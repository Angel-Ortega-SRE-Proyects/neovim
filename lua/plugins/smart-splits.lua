-- Navegación de splits que cruza la frontera Neovim <-> panes de tmux
-- (requiere el snippet en ~/.tmux.conf que reenvía C-hjkl al pane activo).
return {
  "mrjones2014/smart-splits.nvim",
  lazy = false,
  opts = {
    ignored_filetypes = { "NvimTree" },
    multiplexer_integration = "tmux",
  },
  keys = {
    -- mode = { "n", "t" }: en modo terminal (dentro de :Term, :Claude,
    -- :Codex, :OpenCode) <C-h/j/k/l> y <C-Flecha> por defecto se le mandan
    -- al shell/proceso en vez de mover el foco -- con "t" se interceptan
    -- también ahí, para poder salir del pane sin soltar antes el terminal.
    { "<C-h>", function() require("smart-splits").move_cursor_left() end, mode = { "n", "t" }, desc = "Ir a split/pane izquierdo" },
    { "<C-j>", function() require("smart-splits").move_cursor_down() end, mode = { "n", "t" }, desc = "Ir a split/pane inferior" },
    { "<C-k>", function() require("smart-splits").move_cursor_up() end, mode = { "n", "t" }, desc = "Ir a split/pane superior" },
    { "<C-l>", function() require("smart-splits").move_cursor_right() end, mode = { "n", "t" }, desc = "Ir a split/pane derecho" },
    { "<C-Left>", function() require("smart-splits").move_cursor_left() end, mode = { "n", "t" }, desc = "Ir a split/pane izquierdo (flecha)" },
    { "<C-Down>", function() require("smart-splits").move_cursor_down() end, mode = { "n", "t" }, desc = "Ir a split/pane inferior (flecha)" },
    { "<C-Up>", function() require("smart-splits").move_cursor_up() end, mode = { "n", "t" }, desc = "Ir a split/pane superior (flecha)" },
    { "<C-Right>", function() require("smart-splits").move_cursor_right() end, mode = { "n", "t" }, desc = "Ir a split/pane derecho (flecha)" },
    { "<M-Left>", function() require("smart-splits").resize_left() end, desc = "Resize split izquierda" },
    { "<M-Down>", function() require("smart-splits").resize_down() end, desc = "Resize split abajo" },
    { "<M-Up>", function() require("smart-splits").resize_up() end, desc = "Resize split arriba" },
    { "<M-Right>", function() require("smart-splits").resize_right() end, desc = "Resize split derecha" },
  },
}
