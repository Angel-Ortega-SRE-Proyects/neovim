-- Menú flotante con los atajos de <leader> disponibles, para no tener que
-- memorizar todo lo que se fue acumulando en config/keymaps.lua y en cada
-- plugin. Los grupos de abajo son solo etiquetas para el menú (no crean
-- mappings) — deben coincidir con los prefijos ya usados en el resto de
-- la config.
return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  opts = {
    preset = "modern",
  },
  config = function(_, opts)
    local wk = require("which-key")
    wk.setup(opts)
    wk.add({
      { "<leader>a", group = "AI CLI (Claude/Codex/OpenCode)" },
      { "<leader>f", group = "Find (telescope)" },
      { "<leader>g", group = "Git" },
      { "<leader>h", group = "Git hunk (gitsigns)" },
      { "<leader>t", group = "Terminal" },
      { "<leader>l", group = "Diagnósticos/LSP list" },
      { "<leader>S", group = "Sesión (persistence)" },
      { "<leader>m", group = "Markdown" },
      { "<leader>b", group = "Buffer" },
    })
  end,
}
