-- Agregador de sesiones de agentes para el Agent Hub. Solo consulta los
-- proveedores cuya CLI está instalada (ejecutable en $PATH), y cachea el
-- listado unos segundos: el spinner del hub vuelve a renderizar varias veces
-- por segundo y no conviene re-escanear el disco en cada frame.
local M = {}
local CACHE_TTL = 2

local PROVIDERS = {
  { kind = "Claude Code", cmd = "claude", module = "config.agent_sessions.claude" },
  { kind = "Codex", cmd = "codex", module = "config.codex_sessions" },
  { kind = "OpenCode", cmd = "opencode", module = "config.agent_sessions.opencode" },
  { kind = "Gemini", cmd = "gemini", module = "config.agent_sessions.gemini" },
  { kind = "Copilot", cmd = "copilot", module = "config.agent_sessions.copilot" },
  { kind = "Grok", cmd = "grok", module = "config.agent_sessions.grok" },
}

local cache = { at = -math.huge, sessions = {} }

local function now()
  return vim.uv.now() / 1000
end

---@param cmd string
---@return boolean
function M.is_installed(cmd)
  return type(cmd) == "string" and vim.fn.executable(cmd) == 1
end

--- Proveedores cuya CLI está disponible en el sistema.
---@return table[]
function M.providers()
  local available = {}
  for _, provider in ipairs(PROVIDERS) do
    if M.is_installed(provider.cmd) then
      local ok, module = pcall(require, provider.module)
      if ok then
        table.insert(available, { kind = provider.kind, cmd = provider.cmd, impl = module })
      end
    end
  end
  return available
end

local function provider_for(session)
  local kind = session and session.kind or "Codex"
  for _, provider in ipairs(PROVIDERS) do
    if provider.kind == kind then
      local ok, module = pcall(require, provider.module)
      return ok and module or nil
    end
  end
  return nil
end

local function collect()
  local sessions = {}
  for _, provider in ipairs(M.providers()) do
    local ok, list = pcall(provider.impl.list)
    if ok and type(list) == "table" then
      for _, session in ipairs(list) do
        session.kind = session.kind or provider.kind
        table.insert(sessions, session)
      end
    else
      vim.notify_once("Agent Hub: no se pudieron leer las sesiones de " .. provider.kind,
        vim.log.levels.WARN)
    end
  end
  table.sort(sessions, function(left, right)
    return (left.updated_at or 0) > (right.updated_at or 0)
  end)
  return sessions
end

--- Descarta el caché (p. ej. tras eliminar una sesión).
function M.invalidate()
  cache.at = -math.huge
  for _, provider in ipairs(PROVIDERS) do
    local module = package.loaded[provider.module]
    if type(module) == "table" and type(module.invalidate) == "function" then
      module.invalidate()
    end
  end
end

---@return table[]
function M.list()
  if now() - cache.at >= CACHE_TTL then
    cache = { at = now(), sessions = collect() }
  end
  return cache.sessions
end

---@return table[]
function M.grouped()
  local projects = require("config.projects")
  local by_path, groups = {}, {}
  for _, session in ipairs(M.list()) do
    local group = by_path[session.cwd]
    if not group then
      group = { path = session.cwd, name = projects.name_for(session.cwd), sessions = {}, updated_at = 0 }
      by_path[session.cwd] = group
      table.insert(groups, group)
    end
    table.insert(group.sessions, session)
    group.updated_at = math.max(group.updated_at, session.updated_at or 0)
  end
  table.sort(groups, function(left, right) return left.updated_at > right.updated_at end)
  return groups
end

---@param session table
---@return string "ejecutando" | "activo" | "detenido"
function M.status(session)
  local provider = provider_for(session)
  if provider and type(provider.status) == "function" then
    local ok, status = pcall(provider.status, session)
    if ok and status then return status end
  end
  return session and session.active and "activo" or "detenido"
end

---@param session table
---@return boolean
function M.remove(session)
  local provider = provider_for(session)
  if not provider or type(provider.remove) ~= "function" then return false end
  local ok, removed = pcall(provider.remove, session)
  M.invalidate()
  return ok and removed == true
end

return M
