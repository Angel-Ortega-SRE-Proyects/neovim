-- Recuerda los buffers abiertos por directorio (cwd), para no tener que
-- volver a abrir todo a mano al retomar un proyecto.
return {
  "folke/persistence.nvim",
  event = "BufReadPre",
  opts = {},
}
