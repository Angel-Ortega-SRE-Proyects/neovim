-- Puente de solo-lectura entre lua/plugins/ai_cli.lua (dueño del estado
-- real de los agentes) y lua/config/statusline.lua (que solo necesita los
-- conteos para pintar el indicador). ai_cli.lua llama a M.set(...) cada vez
-- que cambia algo; nadie más debería escribir acá.
local M = { visible = 0, hidden = 0 }

function M.set(visible, hidden)
  M.visible = visible
  M.hidden = hidden
end

return M
