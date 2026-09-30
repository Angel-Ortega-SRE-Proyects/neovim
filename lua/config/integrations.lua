-- Flags uniformes para activar o desactivar integraciones sin editar los
-- módulos base. La variable global de Neovim tiene prioridad sobre el entorno.
local M = {}

local function as_boolean(value)
  if type(value) == "boolean" then return value end
  if type(value) ~= "string" then return nil end
  value = value:lower()
  if value == "0" or value == "false" or value == "no" or value == "off" then
    return false
  end
  if value == "1" or value == "true" or value == "yes" or value == "on" then
    return true
  end
  return nil
end

function M.enabled(name, default)
  local global = as_boolean(vim.g["nvim_enable_" .. name])
  if global ~= nil then return global end

  local environment = as_boolean(vim.env["NVIM_ENABLE_" .. name:upper()])
  if environment ~= nil then return environment end

  return default ~= false
end

return M
