-- GitHub Copilot. La primera vez ejecuta :Copilot auth para iniciar sesión.
-- Sugerencia en "ghost text" (texto fantasma), como en VSCode:
--   <Tab>   acepta la sugerencia de Copilot si hay una visible
--           (si no, se comporta como el <Tab> normal de nvim-cmp)
--   <M-]>   siguiente sugerencia
--   <M-[>   sugerencia anterior
--   <C-]>   descartar sugerencia (ghost-text Y NES, ver abajo)
--
-- NES (Next Edit Suggestions): a diferencia de la ghost-text (que solo
-- completa donde estás escribiendo), NES te propone el PRÓXIMO cambio
-- relacionado en otra parte del archivo -- necesita copilot-lsp aparte
-- (no viene con copilot.lua):
--   <M-CR>  aceptar y saltar a la sugerencia
--   <C-]>   descartar (mismo atajo que la ghost-text)
--
-- Icono de estado en la barra de abajo (● listo, ◐ pensando, ○ apagado/sin
-- auth, ✕ error) -- ver lua/config/statusline.lua.
return {
  "zbirenbaum/copilot.lua",
  cmd = "Copilot",
  event = "InsertEnter",
  dependencies = { "copilotlsp-nvim/copilot-lsp" },
  opts = {
    logger = {
      file = vim.fn.stdpath("log") .. "/copilot-lua.log",
      file_log_level = vim.log.levels.TRACE,
      print_log_level = vim.log.levels.WARN,
      trace_lsp = "verbose",
      trace_lsp_progress = true,
      log_lsp_messages = true,
    },
    suggestion = {
      enabled = true,
      auto_trigger = true,
      keymap = {
        accept = false, -- lo maneja lua/plugins/cmp.lua para no chocar con <Tab>
        next = "<M-]>",
        prev = "<M-[>",
        dismiss = "<C-]>",
      },
    },
    nes = {
      enabled = true,
      auto_trigger = true,
      keymap = {
        accept_and_goto = "<M-CR>",
        accept = false,
        dismiss = "<C-]>",
      },
    },
    panel = { enabled = false },
    -- gitcommit viene DESHABILITADO por defecto adentro de copilot.lua
    -- (internal_filetypes) -- sin esto no sugiere nada al escribir el
    -- mensaje de un commit (`git commit` sin -m, abre COMMIT_EDITMSG acá).
    filetypes = {
      gitcommit = true,
    },
  },
  config = function(_, opts)
    require("copilot").setup(opts)
    -- Empuja cada cambio de estado del LSP de Copilot (Normal/InProgress/
    -- Warning, o vacío al arrancar) a config/copilot_status.lua, que la
    -- statusline lee para pintar el ícono -- mismo patrón que
    -- config/agents_status.lua para el indicador de agentes de IA.
    require("copilot.status").register_status_notification_handler(function(data)
      require("config.copilot_status").set(data)
    end)
  end,
}
