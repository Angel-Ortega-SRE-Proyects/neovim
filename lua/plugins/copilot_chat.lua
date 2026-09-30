-- CopilotChat.nvim -- usa el endpoint de CHAT de Copilot (generación de
-- texto libre a partir de un prompt), a diferencia de zbirenbaum/copilot.lua
-- (ghost-text/inline, pensado para continuar código mientras escribís).
--
-- config/git_commit.lua lo usa headless (sin abrir la ventana de chat) para
-- generar el mensaje de commit: el ghost-text de copilot.lua devolvía
-- `completions = {}` de forma consistente y reproducible para el filetype
-- `gitcommit` (languageId normalizado a "git-commit") -- confirmado con
-- código funcionando normal en otros filetypes, así que no es un problema
-- de configuración sino una limitación de ese endpoint para este caso de uso.
if not require("config.integrations").enabled("copilot_chat") then return {} end

return {
  "CopilotC-Nvim/CopilotChat.nvim",
  branch = "main",
  dependencies = {
    { "zbirenbaum/copilot.lua" },
    { "nvim-lua/plenary.nvim" },
  },
  cmd = { "CopilotChat" },
  opts = {},
}
