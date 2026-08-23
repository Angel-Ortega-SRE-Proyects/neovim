-- Formateo al guardar. Si no hay formatter externo instalado para el
-- filetype, cae al del LSP attacheado (lsp_format = "fallback") en vez de
-- fallar en silencio.
return {
  "stevearc/conform.nvim",
  event = { "BufWritePre" },
  cmd = "ConformInfo",
  keys = {
    {
      "<leader>cf",
      function() require("conform").format({ async = true, lsp_format = "fallback" }) end,
      mode = { "n", "v" },
      desc = "Formatear archivo/selección",
    },
  },
  opts = {
    formatters_by_ft = {
      lua = { "stylua" },
      bash = { "shfmt" },
      sh = { "shfmt" },
      json = { "prettier" },
      yaml = { "prettier" },
      markdown = { "prettier" },
      dockerfile = { "prettier" },
      terraform = { "terraform_fmt" },
      -- ruff_format primero (rápido); si no está instalado, conform sigue
      -- a black solo (no corre ambos: son alternativas, no un pipeline).
      python = { "ruff_format", "black", stop_after_first = true },
      javascript = { "prettier" },
      typescript = { "prettier" },
      javascriptreact = { "prettier" },
      typescriptreact = { "prettier" },
      go = { "gofmt" },
      java = { "google-java-format" },
      cs = { "csharpier" },
    },
    format_on_save = {
      lsp_format = "fallback",
      timeout_ms = 1000,
    },
  },
}
