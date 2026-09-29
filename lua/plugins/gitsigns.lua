-- Señales de git en el gutter (líneas agregadas/modificadas/borradas) +
-- stage/reset por hunk. Complementa a diffview (lua/plugins/diffview.lua,
-- vista completa de diffs) y telescope (lua/plugins/telescope.lua, log de
-- commits): esto es para el día a día, mientras editás.
local t = require("config.i18n").t

return {
  "lewis6991/gitsigns.nvim",
  event = { "BufReadPre", "BufNewFile" },
  opts = {
    signs = {
      add = { text = "│" },
      change = { text = "│" },
      delete = { text = "_" },
      topdelete = { text = "‾" },
      changedelete = { text = "~" },
    },
    on_attach = function(bufnr)
      local gs = require("gitsigns")
      local map = function(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
      end

      map("n", "]h", gs.next_hunk, t("Siguiente cambio"))
      map("n", "[h", gs.prev_hunk, t("Cambio anterior"))
      map("n", "<leader>hs", gs.stage_hunk, t("Preparar cambio"))
      map("n", "<leader>hr", gs.reset_hunk, t("Restablecer cambio"))
      map("v", "<leader>hs", function() gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, t("Preparar cambio (selección)"))
      map("v", "<leader>hr", function() gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, t("Restablecer cambio (selección)"))
      map("n", "<leader>hS", gs.stage_buffer, t("Preparar todo el archivo"))
      map("n", "<leader>hR", gs.reset_buffer, t("Restablecer todo el archivo"))
      map("n", "<leader>hp", gs.preview_hunk, t("Vista previa del cambio"))
      map("n", "<leader>hb", function() gs.blame_line({ full = true }) end, t("Autoría de la línea"))
    end,
  },
}
