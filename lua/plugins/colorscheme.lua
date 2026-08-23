return {
  "folke/tokyonight.nvim",
  lazy = false,
  priority = 1000,
  config = function()
    vim.cmd.colorscheme("tokyonight")

    -- Highlights base (StatusLine, CursorLine, Visual, Search, etc.) de la
    -- paleta verde/café/negro centralizada en lua/config/theme.lua. Se
    -- reaplica en cada ColorScheme porque cambiar de tema los pisa.
    local theme = require("config.theme")
    theme.apply_base_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("ThemeBaseHighlights", { clear = true }),
      callback = theme.apply_base_highlights,
    })
  end,
}
