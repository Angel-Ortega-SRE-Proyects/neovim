-- GitHub Copilot. La primera vez ejecuta :Copilot auth para iniciar sesión.
-- Sugerencia en "ghost text" (texto fantasma), como en VSCode:
--   <Tab>   acepta la sugerencia de Copilot si hay una visible
--           (si no, se comporta como el <Tab> normal de nvim-cmp)
--   <M-]>   siguiente sugerencia
--   <M-[>   sugerencia anterior
--   <C-]>   descartar sugerencia
return {
  "zbirenbaum/copilot.lua",
  cmd = "Copilot",
  event = "InsertEnter",
  opts = {
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
    panel = { enabled = false },
  },
}
