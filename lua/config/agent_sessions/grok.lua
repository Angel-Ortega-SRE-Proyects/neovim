-- Sesiones de Grok CLI: ~/.grok/sessions/<cwd codificado>/<id>/summary.json.
-- El título sale de session_summary o del primer prompt en prompt_history.jsonl.
local util = require("config.agent_sessions.util")

local M = { kind = "Grok", cmd = "grok" }

local function root()
  return vim.fn.expand("~/.grok/sessions")
end

local function active_path()
  return vim.fn.expand("~/.grok/active_sessions.json")
end

local function read_prompts(path)
  local prompts = {}
  util.each_json_line(path, function(entry)
    if entry.session_id and not prompts[entry.session_id] and not entry.is_bash
        and util.is_user_prompt(entry.prompt) then
      prompts[entry.session_id] = entry.prompt
    end
  end, '"prompt"')
  return prompts
end

local function read_summary(path)
  local data = util.read_json(path)
  local info = data and data.info
  if type(info) ~= "table" or not info.id or not info.cwd then return false end
  local summary = data.session_summary
  return {
    id = info.id,
    cwd = info.cwd,
    title = type(summary) == "string" and summary ~= "" and summary or nil,
    updated_at = util.iso_to_epoch(data.last_active_at or data.updated_at),
  }
end

local function project_sessions(project, sessions)
  local prompts = util.cached(project .. "/prompt_history.jsonl", read_prompts) or {}
  for id, kind in util.scandir(project) do
    if kind == "directory" then
      local path = project .. "/" .. id
      local meta, stat = util.cached(path .. "/summary.json", read_summary)
      if meta then
        table.insert(sessions, util.session({
          kind = M.kind, label = "Grok", id = meta.id,
          title = meta.title or prompts[meta.id], cwd = meta.cwd, path = path,
          updated_at = math.max(meta.updated_at, util.mtime(path .. "/chat_history.jsonl"),
            stat.mtime.sec),
          cmd = { "grok", "--resume", meta.id },
        }))
      end
    end
  end
end

---@return table[]
function M.list()
  local sessions = {}
  for dir, kind in util.scandir(root()) do
    if kind == "directory" then project_sessions(root() .. "/" .. dir, sessions) end
  end
  return sessions
end

local function is_open(session_id)
  local file = io.open(active_path(), "r")
  if not file then return false end
  local raw = file:read("*a") or ""
  file:close()
  return raw:find(session_id, 1, true) ~= nil
end

---@param session table
---@return string
function M.status(session)
  local status = util.time_status(session.updated_at)
  if status == "detenido" and is_open(session.session_id) then return "activo" end
  return status
end

---@param session table
---@return boolean
function M.remove(session)
  vim.fn.system({ "grok", "sessions", "delete", session.session_id })
  return vim.v.shell_error == 0
end

return M
