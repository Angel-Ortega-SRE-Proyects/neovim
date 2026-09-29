-- Navegación de splits que cruza la frontera Neovim <-> panes de tmux
-- (requiere el snippet en ~/.tmux.conf que reenvía C-Flechas al pane activo).
local t = require("config.i18n").t

return {
  "mrjones2014/smart-splits.nvim",
  lazy = false,
  opts = {
    ignored_filetypes = { "NvimTree" },
    multiplexer_integration = "tmux",
  },
  keys = {
    -- mode = { "n", "t" }: en modo terminal (dentro de :Term, :Claude,
    -- :Codex, :OpenCode) <C-Flecha> por defecto se le mandan
    -- al shell/proceso en vez de mover el foco -- con "t" se interceptan
    -- también ahí, para poder salir del pane sin soltar antes el terminal.
    { "<C-Left>", function() require("smart-splits").move_cursor_left() end, mode = { "n", "t" }, desc = t("Ir a división/panel izquierdo (flecha)") },
    { "<C-Down>", function() require("smart-splits").move_cursor_down() end, mode = { "n", "t" }, desc = t("Ir a división/panel inferior (flecha)") },
    { "<C-Up>", function() require("smart-splits").move_cursor_up() end, mode = { "n", "t" }, desc = t("Ir a división/panel superior (flecha)") },
    { "<C-Right>", function() require("smart-splits").move_cursor_right() end, mode = { "n", "t" }, desc = t("Ir a división/panel derecho (flecha)") },
  },
}
