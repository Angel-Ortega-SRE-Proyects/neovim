-- Sesiones de Claude Code: ~/.claude/projects/<cwd codificado>/<uuid>.jsonl.
-- El estado en vivo sale de ~/.claude/sessions/<pid>.json (status busy/idle).
local util = require("config.agent_sessions.util")

local M = { kind = "Claude Code", cmd = "claude" }
local MAX_LINES = 400
local REGISTRY_TTL = 1

local registry = { at = -1, by_id = {} }

local function root()
  return vim.fn.expand("~/.claude/projects")
end

local function registry_dir()
  return vim.fn.expand("~/.claude/sessions")
end

local function read_session(path)
  local id, cwd, title
  util.each_json_line(path, function(entry)
    if entry.isSidechain then return false end
    id = id or entry.sessionId
    cwd = cwd or entry.cwd
    if entry.type == "user" and not entry.isMeta and type(entry.message) == "table" then
      title = title or util.prompt_from_content(entry.message.content)
    end
    return id ~= nil and cwd ~= nil and title ~= nil
  end, '"cwd"', MAX_LINES)
  if not id or not cwd then return false end
  return { id = id, cwd = cwd, title = title }
end

---@return table[]
function M.list()
  local sessions = {}
  for dir, dir_kind in util.scandir(root()) do
    if dir_kind == "directory" then
      local project = root() .. "/" .. dir
      for name, kind in util.scandir(project) do
        if kind == "file" and name:match("%.jsonl$") then
          local path = project .. "/" .. name
          local meta, stat = util.cached(path, read_session)
          if meta then
            table.insert(sessions, util.session({
              kind = M.kind, label = "Claude", id = meta.id, title = meta.title,
              cwd = meta.cwd, path = path, updated_at = stat.mtime.sec,
              cmd = { "claude", "--resume", meta.id },
            }))
          end
        end
      end
    end
  end
  return sessions
end

local function live_sessions()
  local now = vim.uv.now() / 1000
  if now - registry.at < REGISTRY_TTL then return registry.by_id end
  local by_id = {}
  for name, kind in util.scandir(registry_dir()) do
    if kind == "file" and name:match("%.json$") then
      local data = util.read_json(registry_dir() .. "/" .. name)
      if data and data.sessionId and util.pid_alive(data.pid) then
        by_id[data.sessionId] = data
      end
    end
  end
  registry = { at = now, by_id = by_id }
  return by_id
end

--- Fuerza a releer el registro de procesos vivos en la próxima consulta.
function M.invalidate()
  registry.at = -1
end

---@param session table
---@return string
function M.status(session)
  if vim.fn.isdirectory(registry_dir()) ~= 1 then
    return util.time_status(session.updated_at)
  end
  local live = live_sessions()[session.session_id]
  if not live then return "detenido" end
  return live.status == "busy" and "ejecutando" or "activo"
end

---@param session table
---@return boolean
function M.remove(session)
  return type(session.path) == "string" and os.remove(session.path) ~= nil
end

return M
