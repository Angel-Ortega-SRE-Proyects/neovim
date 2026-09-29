-- Menú flotante con los atajos de <leader> disponibles, para no tener que
-- memorizar todo lo que se fue acumulando en config/keymaps.lua y en cada
-- plugin. Los grupos de abajo son solo etiquetas para el menú (no crean
-- mappings) — deben coincidir con los prefijos ya usados en el resto de
-- la config.
-- wk.add() solo corre una vez, en config(), disparado por el evento
-- VeryLazy al arrancar Neovim -- por eso las etiquetas del spec (a
-- diferencia de los `desc` de config/keymaps.lua, que sí se re-evalúan en
-- :ConfigReload) quedaban congeladas en el idioma inicial. M.refresh_i18n
-- re-arma el spec con el t() vigente; init.lua la llama tras recargar.
local function i18n_spec()
  local t = require("config.i18n").t
  return {
    { "<leader>a", group = t("Centro de agentes") },
    { "<leader>aq", desc = "Cerrar AgentHub" },
    { "<leader>f", group = t("Búsqueda (Telescope)") },
    { "<leader>g", group = t("Git / Copilot") },
    { "<leader>gg", desc = t("Abrir modo Git") },
    { "<leader>gc", desc = t("Abrir GitHub Copilot") },
    { "<leader>h", group = t("Cambios de Git (gitsigns)") },
    { "<leader>t", group = t("Terminal") },
    { "<leader>l", group = t("Lista de diagnósticos/LSP") },
    { "<leader>m", group = t("Markdown") },
    { "<leader>p", group = t("Proyectos") },
    { "<leader>u", group = t("Interfaz") },
    { "<leader>uc", desc = t("Cambiar tema de colores") },
    { "<leader>ul", desc = t("Cambiar idioma de la interfaz") },
  }
end

local M = {
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
    wk.add(i18n_spec())
  end,
}

function M.refresh_i18n()
  local ok, wk = pcall(require, "which-key")
  if ok then wk.add(i18n_spec()) end
end

return M
