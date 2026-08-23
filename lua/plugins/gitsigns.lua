-- Señales de git en el gutter (líneas agregadas/modificadas/borradas) +
-- stage/reset por hunk. Complementa a diffview (lua/plugins/diffview.lua,
-- vista completa de diffs) y telescope (lua/plugins/telescope.lua, log de
-- commits): esto es para el día a día, mientras editás.
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

      map("n", "]h", gs.next_hunk, "Siguiente hunk")
      map("n", "[h", gs.prev_hunk, "Hunk anterior")
      map("n", "<leader>hs", gs.stage_hunk, "Stage hunk")
      map("n", "<leader>hr", gs.reset_hunk, "Reset hunk")
      map("v", "<leader>hs", function() gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, "Stage hunk (selección)")
      map("v", "<leader>hr", function() gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, "Reset hunk (selección)")
      map("n", "<leader>hS", gs.stage_buffer, "Stage todo el archivo")
      map("n", "<leader>hR", gs.reset_buffer, "Reset todo el archivo")
      map("n", "<leader>hp", gs.preview_hunk, "Preview hunk")
      map("n", "<leader>hb", function() gs.blame_line({ full = true }) end, "Blame de la línea")
    end,
  },
}
