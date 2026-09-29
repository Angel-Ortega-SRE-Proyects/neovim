-- Sesiones de OpenCode: tabla `session` de ~/.local/share/opencode/opencode.db
-- (SQLite). Se consulta en modo solo-lectura con el binario sqlite3.
local util = require("config.agent_sessions.util")

local M = { kind = "OpenCode", cmd = "opencode" }
local QUERY = "select id, title, directory, time_updated from session"
  .. " where parent_id is null and time_archived is null"
  .. " order by time_updated desc limit 200"

local cache = { key = nil, rows = {} }

local function db_path()
  return vim.fn.expand("~/.local/share/opencode/opencode.db")
end

local function db_key(path)
  -- El WAL cambia antes que el archivo principal mientras OpenCode escribe.
  return util.mtime(path) .. ":" .. util.mtime(path .. "-wal")
end

local function query_rows(path)
  if vim.fn.executable("sqlite3") ~= 1 then return {} end
  local output = vim.fn.system({ "sqlite3", "-readonly", "-json", path, QUERY })
  if vim.v.shell_error ~= 0 or vim.trim(output) == "" then return {} end
  local ok, rows = pcall(vim.json.decode, output)
  return ok and type(rows) == "table" and rows or {}
end

---@return table[]
function M.list()
  local path = db_path()
  if vim.fn.filereadable(path) ~= 1 then return {} end
  local key = db_key(path)
  if cache.key ~= key then
    cache = { key = key, rows = query_rows(path) }
  end
  local sessions = {}
  for _, row in ipairs(cache.rows) do
    if row.id and row.directory then
      table.insert(sessions, util.session({
        kind = M.kind, label = "OpenCode", id = row.id, title = row.title,
        cwd = row.directory, path = path,
        updated_at = math.floor((tonumber(row.time_updated) or 0) / 1000),
        cmd = { "opencode", "-s", row.id },
      }))
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
  vim.fn.system({ "opencode", "session", "delete", session.session_id })
  cache.key = nil
  return vim.v.shell_error == 0
end

return M
