-- Sesiones de Gemini CLI: ~/.gemini/tmp/<proyecto>/chats/session-*.jsonl.
-- La ruta real del proyecto está en ~/.gemini/tmp/<proyecto>/.project_root.
local util = require("config.agent_sessions.util")

local M = { kind = "Gemini", cmd = "gemini" }
local MAX_LINES = 200

local function root()
  return vim.fn.expand("~/.gemini/tmp")
end

local function project_root(dir)
  local file = io.open(dir .. "/.project_root", "r")
  if not file then return nil end
  local cwd = vim.trim(file:read("*a") or "")
  file:close()
  return cwd ~= "" and cwd or nil
end

local function message_prompt(message)
  if type(message) ~= "table" or message.type ~= "user" then return nil end
  return util.prompt_from_content(message.content)
end

local function read_session(path)
  local meta, title
  util.each_json_line(path, function(entry)
    if not meta then
      meta = entry
      return false
    end
    title = title or message_prompt(entry)
    local set = entry["$set"]
    for _, message in ipairs(type(set) == "table" and set.messages or {}) do
      title = title or message_prompt(message)
    end
    return title ~= nil
  end, nil, MAX_LINES)
  -- Las sesiones del servidor A2A (sessionId "a2a-server") no son interactivas.
  if not meta or type(meta.sessionId) ~= "string" or not meta.sessionId:match("^%x+%-%x+")
      or (meta.kind and meta.kind ~= "main") then
    return false
  end
  return { id = meta.sessionId, title = title }
end

---@return table[]
function M.list()
  local sessions = {}
  for dir, dir_kind in util.scandir(root()) do
    local project = root() .. "/" .. dir
    local cwd = dir_kind == "directory" and project_root(project) or nil
    if cwd then
      for name, kind in util.scandir(project .. "/chats") do
        if kind == "file" and name:match("%.jsonl$") then
          local path = project .. "/chats/" .. name
          local meta, stat = util.cached(path, read_session)
          if meta then
            table.insert(sessions, util.session({
              kind = M.kind, label = "Gemini", id = meta.id, title = meta.title,
              cwd = cwd, path = path, updated_at = stat.mtime.sec,
              cmd = { "gemini", "--resume", meta.id },
            }))
          end
        end
      end
    end
  end
  return sessions
end

---@param session table
---@return string
function M.status(session)
  return util.time_status(session.updated_at)
end

---@param session table
---@return boolean
function M.remove(session)
  return type(session.path) == "string" and os.remove(session.path) ~= nil
end

return M
