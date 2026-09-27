-- Menú flotante con los atajos de <leader> disponibles, para no tener que
-- memorizar todo lo que se fue acumulando en config/keymaps.lua y en cada
-- plugin. Los grupos de abajo son solo etiquetas para el menú (no crean
-- mappings) — deben coincidir con los prefijos ya usados en el resto de
-- la config.
return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  keys = {
    { "<leader>", mode = { "n", "v" } },
  },
  opts = {
    preset = "modern",
    delay = 0,
    triggers = {
      { "<leader>", mode = { "n", "v" } },
    },
  },
  config = function(_, opts)
    local wk = require("which-key")
    wk.setup(opts)
    wk.add({
      { "<leader>a", group = "Agent Hub" },
      { "<leader>f", group = "Find (telescope)" },
      { "<leader>g", group = "Git" },
      { "<leader>h", group = "Git hunk (gitsigns)" },
      { "<leader>t", group = "Terminal" },
      { "<leader>l", group = "Diagnósticos/LSP list" },
      { "<leader>S", group = "Sesión (persistence)" },
      { "<leader>m", group = "Markdown" },
      { "<leader>p", group = "Proyectos" },
      { "<leader>u", group = "Interfaz" },
      { "<leader>uc", desc = "Cambiar tema de colores" },
    })
  end,
}
