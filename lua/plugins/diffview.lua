-- Panel de cambios de git (como el "Source Control" de VSCode):
--   :DiffviewOpen           ver todos los archivos modificados + diff
--   :DiffviewFileHistory %  historial del archivo actual
--   :DiffviewClose          cerrar
return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
  keys = {
    { "<leader>gd", function() require("config.git").guard("DiffviewOpen")() end, desc = "Git: ver cambios (diff)" },
    { "<leader>gh", function() require("config.git").guard("DiffviewFileHistory %")() end, desc = "Git: historial del archivo" },
  },
  opts = {},
}
