-- Panel de diagnósticos/quickfix, en vez de saltar de a uno con
-- vim.diagnostic.goto_next. Complementa <leader>d (lsp.lua), que muestra
-- el float puntual de la línea actual.
local t = require("config.i18n").t

return {
  "folke/trouble.nvim",
  cmd = "Trouble",
  keys = {
    { "<leader>ld", "<cmd>Trouble diagnostics toggle<CR>", desc = t("Diagnósticos (espacio de trabajo)") },
    { "<leader>lD", "<cmd>Trouble diagnostics toggle filter.buf=0<CR>", desc = t("Diagnósticos (buffer actual)") },
    { "<leader>lq", "<cmd>Trouble qflist toggle<CR>", desc = t("Lista de correcciones rápidas") },
  },
  opts = {},
}
