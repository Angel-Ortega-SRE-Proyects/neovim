-- Utilidades compartidas por los proveedores de sesiones de agentes
-- (Claude, OpenCode, Gemini, Copilot, Grok). Cada proveedor lee el
-- almacenamiento local de su CLI y devuelve entradas con la misma forma que
-- config.codex_sessions, así el Agent Hub las trata de forma uniforme.
local M = {}
local platform = require("config.platform")

M.ACTIVE_WINDOW = 15 * 60
M.EXECUTING_WINDOW = 5

local file_cache = {} -- path -> { mtime, size, value }

---@param text string|nil
---@param fallback string
---@return string
function M.compact_title(text, fallback)
  text = vim.trim((text or ""):gsub("%s+", " "))
  if text == "" then return fallback end
  if vim.fn.strchars(text) > 52 then
    return vim.fn.strcharpart(text, 0, 49) .. "..."
  end
  return text
end

--- Descarta textos inyectados por las CLIs o hooks (contexto, recordatorios).
---@param text any
---@return boolean
function M.is_user_prompt(text)
  if type(text) ~= "string" then return false end
  local trimmed = vim.trim(text)
  if trimmed == "" or trimmed:sub(1, 1) == "<" then return false end
  return not (trimmed:match("^# AGENTS%.md") or trimmed:match("^╔─ HIGPERTEXT")
    or trimmed:match("^Caveat:"))
end

--- Primer texto de usuario válido en un content (string o lista de bloques).
---@param content any
---@return string|nil
function M.prompt_from_content(content)
  if M.is_user_prompt(content) then return content end
  if type(content) ~= "table" then return nil end
  for _, block in ipairs(content) do
    local text = type(block) == "table" and block.text or nil
    if M.is_user_prompt(text) then return text end
  end
  return nil
end

---@param path string
---@return string
function M.normalize_cwd(path)
  local cwd = vim.fn.fnamemodify(path, ":p")
  if platform.is_windows then cwd = cwd:gsub("\\", "/") end
  if cwd ~= "/" then cwd = cwd:gsub("[/\\]+$", "") end
  return cwd
end

local function utc_offset()
  local now = os.time()
  return os.difftime(now, os.time(os.date("!*t", now)))
end

--- Convierte "2026-09-26T00:49:48.247Z" (UTC) a epoch en segundos.
---@param iso any
---@return integer
function M.iso_to_epoch(iso)
  if type(iso) ~= "string" then return 0 end
  local y, mo, d, h, mi, s = iso:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return 0 end
  local local_time = os.time({
    year = tonumber(y), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h), min = tonumber(mi), sec = tonumber(s), isdst = false,
  })
  return math.floor(local_time + utc_offset())
end

---@param path string
---@return table|nil
function M.read_json(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local raw = file:read("*a")
  file:close()
  local ok, decoded = pcall(vim.json.decode, raw)
  return ok and type(decoded) == "table" and decoded or nil
end

--- Recorre las líneas JSON de un archivo hasta que `visit` devuelva true.
---@param path string
---@param visit fun(entry: table, line: string): boolean|nil
---@param filter string|nil  substring requerido antes de decodificar
---@param max_lines integer|nil
function M.each_json_line(path, visit, filter, max_lines)
  local file = io.open(path, "r")
  if not file then return end
  local count = 0
  for line in file:lines() do
    count = count + 1
    if max_lines and count > max_lines then break end
    if not filter or line:find(filter, 1, true) then
      local ok, entry = pcall(vim.json.decode, line)
      if ok and type(entry) == "table" and visit(entry, line) then break end
    end
  end
  file:close()
end

--- Memoiza `reader(path, stat)` mientras mtime (con nanosegundos) y tamaño
--- no cambien: con solo segundos, reescribir un archivo del mismo tamaño en
--- el mismo segundo devolvía la versión vieja.
---@param path string
---@param reader fun(path: string, stat: table): any
---@return any, table|nil
function M.cached(path, reader)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    file_cache[path] = nil
    return nil, nil
  end
  local mtime = stat.mtime.sec .. "." .. stat.mtime.nsec
  local entry = file_cache[path]
  if entry and entry.mtime == mtime and entry.size == stat.size then
    return entry.value, stat
  end
  local value = reader(path, stat)
  file_cache[path] = { mtime = mtime, size = stat.size, value = value }
  return value, stat
end

---@param path string
---@return fun(): string|nil, string|nil
function M.scandir(path)
  local handle = vim.uv.fs_scandir(path)
  return function()
    if not handle then return nil end
    return vim.uv.fs_scandir_next(handle)
  end
end

---@param path string
---@return integer
function M.mtime(path)
  local stat = vim.uv.fs_stat(path)
  return stat and stat.mtime.sec or 0
end

---@param last_seen integer
---@return string "ejecutando" | "activo" | "detenido"
function M.time_status(last_seen)
  local age = os.time() - (last_seen or 0)
  if last_seen and last_seen > 0 and age <= M.EXECUTING_WINDOW then return "ejecutando" end
  if last_seen and last_seen > 0 and age <= M.ACTIVE_WINDOW then return "activo" end
  return "detenido"
end

---@param pid any
---@return boolean
function M.pid_alive(pid)
  if type(pid) ~= "number" then return false end
  return vim.uv.kill(pid, 0) == 0
end

--- Construye la entrada estándar de sesión externa que consume el Agent Hub.
---@param spec { kind: string, label: string, id: string, title: string|nil, cwd: string, cmd: string[], path: string, updated_at: integer }
---@return table
function M.session(spec)
  local short_id = spec.id:gsub("-", ""):sub(-8)
  local title = M.compact_title(spec.title, "sesión " .. short_id)
  return {
    path = spec.path,
    name = spec.label .. " · " .. title .. " [" .. short_id .. "]",
    kind = spec.kind,
    short_id = short_id,
    cmd = spec.cmd,
    cwd = M.normalize_cwd(spec.cwd),
    action = "agent",
    external = true,
    session_id = spec.id,
    updated_at = spec.updated_at or 0,
  }
end

return M
