-- Panel de cambios de git (como el "Source Control" de VSCode):
--   :DiffviewOpen           ver todos los archivos modificados + diff
--   :DiffviewFileHistory %  historial del archivo actual
--   :DiffviewClose          cerrar
return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
  opts = {},
}
