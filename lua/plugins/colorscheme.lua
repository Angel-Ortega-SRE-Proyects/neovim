return {
  "folke/tokyonight.nvim",
  lazy = false,
  priority = 1000,
  config = function()
    -- TokyoNight aporta la sintaxis y la estructura base; theme.lua aplica
    -- encima la superficie y los acentos del preset elegido.
    local theme = require("config.theme")
    local selected = theme.themes[theme.active] or theme.themes.verde
    vim.cmd.colorscheme(selected.scheme)
    theme.apply_base_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("ThemeBaseHighlights", { clear = true }),
      callback = theme.apply_base_highlights,
    })
  end,
}
