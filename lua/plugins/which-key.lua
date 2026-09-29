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
    local t = require("config.i18n").t
    wk.setup(opts)
    wk.add({
      { "<leader>a", group = t("Centro de agentes") },
      { "<leader>aq", desc = "Cerrar AgentHub" },
      { "<leader>f", group = t("Búsqueda (Telescope)") },
      { "<leader>g", group = t("Git / Copilot") },
      { "<leader>gg", desc = t("Abrir modo Git") },
      { "<leader>gc", desc = t("Abrir GitHub Copilot") },
      { "<leader>h", group = t("Cambios de Git (gitsigns)") },
      { "<leader>t", group = t("Terminal") },
      { "<leader>l", group = t("Lista de diagnósticos/LSP") },
      { "<leader>S", group = t("Sesión (persistence)") },
      { "<leader>m", group = t("Markdown") },
      { "<leader>p", group = t("Proyectos") },
      { "<leader>u", group = t("Interfaz") },
      { "<leader>uc", desc = t("Cambiar tema de colores") },
      { "<leader>ul", desc = t("Cambiar idioma de la interfaz") },
    })
  end,
}
