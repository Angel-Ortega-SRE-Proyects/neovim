-- Sesiones de GitHub Copilot CLI: ~/.copilot/session-state/<uuid>/
-- (workspace.yaml + events.jsonl). Las sesiones abiertas y si están
-- trabajando se leen de ~/.copilot/open-sessions-state.json.
local util = require("config.agent_sessions.util")

local M = { kind = "Copilot", cmd = "copilot" }
local MAX_LINES = 300

local function root()
  return vim.fn.expand("~/.copilot/session-state")
end

local function open_state_path()
  return vim.fn.expand("~/.copilot/open-sessions-state.json")
end

local function read_workspace(path)
  local fields = {}
  local file = io.open(path, "r")
  if not file then return false end
  for line in file:lines() do
    local key, value = line:match("^([%w_]+):%s*(.-)%s*$")
    if key and value ~= "" and value ~= "|-" and value:sub(1, 1) ~= '"' then
      fields[key] = value
    end
  end
  file:close()
  if not fields.id or not fields.cwd then return false end
  return fields
end

local function first_prompt(events_path)
  local title
  util.each_json_line(events_path, function(entry)
    if entry.type == "user.message" and type(entry.data) == "table" then
      title = util.prompt_from_content(entry.data.content)
    end
    return title ~= nil
  end, '"user.message"', MAX_LINES)
  return title or false
end

---@return table[]
function M.list()
  local sessions = {}
  for id, kind in util.scandir(root()) do
    if kind == "directory" then
      local dir = root() .. "/" .. id
      local fields = util.cached(dir .. "/workspace.yaml", read_workspace)
      if fields then
        local events = dir .. "/events.jsonl"
        local prompt, stat = util.cached(events, first_prompt)
        table.insert(sessions, util.session({
          kind = M.kind, label = "Copilot", id = fields.id,
          title = fields.name or prompt or nil, cwd = fields.cwd, path = dir,
          updated_at = stat and stat.mtime.sec or util.iso_to_epoch(fields.updated_at),
          cmd = { "copilot", "--resume=" .. fields.id },
        }))
      end
    end
  end
  return sessions
end

---@param session table
---@return string
function M.status(session)
  local open = util.cached(open_state_path(), util.read_json) or {}
  local live = open[session.session_id]
  local status = util.time_status(session.updated_at)
  if type(live) ~= "table" or status == "detenido" then return status end
  return live.working and "ejecutando" or "activo"
end

---@param session table
---@return boolean
function M.remove(session)
  if type(session.path) ~= "string" or vim.fn.isdirectory(session.path) ~= 1 then
    return false
  end
  return vim.fn.delete(session.path, "rf") == 0
end

return M
