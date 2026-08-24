-- Puente de solo-lectura entre lua/plugins/copilot.lua (que se suscribe al
-- estado real vía copilot.status) y lua/config/statusline.lua (que solo
-- necesita el último valor para pintar el ícono). Mismo patrón que
-- config/agents_status.lua para los agentes de IA.
local M = { status = "", message = "" }

--- data: { status = ''|'Normal'|'InProgress'|'Warning', message = string }
function M.set(data)
  M.status = data.status or ""
  M.message = data.message or ""
end

return M
