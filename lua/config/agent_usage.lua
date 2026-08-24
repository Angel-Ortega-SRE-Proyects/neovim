-- Tokens usados y costo estimado, por agente de IA, en la sesión ACTIVA de
-- cada uno para la carpeta (cwd) actual -- cada herramienta guarda esto en
-- disco de forma distinta, así que hay un parser por herramienta. Se
-- refresca en segundo plano (M.start), lo lee lua/plugins/editor.lua para
-- pintarlo en la barra de arriba, lado izquierdo.
--
-- Precisión: los tokens son el dato real que cada CLI escribió en su
-- propio log/sqlite -- no son una estimación. El COSTO sí es aproximado
-- para Claude/Codex/Gemini/Copilot CLI (tarifa fija por herramienta más
-- abajo en PRICE_PER_1M, revisala si querés más precisión); OpenCode es la
-- única que da el costo real ya calculado por el propio proveedor.
local M = {
  data = {}, -- name -> { tokens = N, cost = N|nil, exact_cost = bool }
}

-- USD por millón de tokens, tarifa única (no por input/output separado)
-- para mantenerlo simple -- son un promedio aproximado del modelo default
-- de cada CLI. Ajustá acá si cambian los precios o el modelo que usás.
local PRICE_PER_1M = {
  claude = 6.0, -- Claude Sonnet, mezcla input/output
  codex = 5.0, -- GPT-5 (Codex CLI), mezcla input/output
  gemini = 0.5, -- Gemini Flash, mezcla input/output
  copilot = 4.0, -- mezcla típica de modelos de Copilot CLI
}

local function estimate_cost(tokens, tool_key)
  local rate = PRICE_PER_1M[tool_key]
  if not rate then
    return nil
  end
  return (tokens / 1000000) * rate
end

local function set(name, tokens, cost, exact_cost)
  M.data[name] = { tokens = tokens or 0, cost = cost, exact_cost = exact_cost or false }
end

-- ---------------------------------------------------------------------
-- Claude Code: ~/.claude/projects/<cwd con "/" -> "-">/*.jsonl -- suma
-- usage de todos los mensajes "assistant" del .jsonl modificado más
-- reciente (la sesión activa).
-- ---------------------------------------------------------------------
local function refresh_claude(cwd)
  local ok = pcall(function()
    local dir = vim.fn.stdpath("data") -- placeholder, sobreescrito abajo
    dir = vim.fn.expand("~/.claude/projects/") .. cwd:gsub("/", "-")
    if vim.fn.isdirectory(dir) ~= 1 then
      set("Claude Code", 0)
      return
    end

    local newest, newest_mtime = nil, -1
    local handle = vim.uv.fs_scandir(dir)
    if not handle then
      set("Claude Code", 0)
      return
    end
    while true do
      local name, typ = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end
      if typ == "file" and name:match("%.jsonl$") then
        local stat = vim.uv.fs_stat(dir .. "/" .. name)
        if stat and stat.mtime.sec > newest_mtime then
          newest_mtime = stat.mtime.sec
          newest = dir .. "/" .. name
        end
      end
    end

    if not newest then
      set("Claude Code", 0)
      return
    end

    local tokens = 0
    local f = io.open(newest, "r")
    if f then
      for line in f:lines() do
        if line ~= "" then
          local decoded_ok, d = pcall(vim.json.decode, line)
          if decoded_ok and d.type == "assistant" and d.message and d.message.usage then
            local u = d.message.usage
            tokens = tokens
              + (u.input_tokens or 0)
              + (u.cache_creation_input_tokens or 0)
              + (u.cache_read_input_tokens or 0)
              + (u.output_tokens or 0)
          end
        end
      end
      f:close()
    end

    set("Claude Code", tokens, estimate_cost(tokens, "claude"))
  end)
  if not ok then
    set("Claude Code", 0)
  end
end

-- ---------------------------------------------------------------------
-- Codex: ~/.codex/sessions/YYYY/MM/DD/*.jsonl (organizado por fecha). Se
-- busca el archivo modificado más reciente en el día más reciente con
-- archivos, se confirma que su session_meta.cwd matchea la carpeta actual,
-- y se toma el ÚLTIMO evento token_count (ya trae el total acumulado, no
-- hay que sumar línea por línea).
-- ---------------------------------------------------------------------
local function newest_entry(dir)
  local newest, newest_mtime = nil, -1
  local handle = vim.uv.fs_scandir(dir)
  if not handle then
    return nil
  end
  while true do
    local name, typ = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    local stat = vim.uv.fs_stat(dir .. "/" .. name)
    if stat and stat.mtime.sec > newest_mtime then
      newest_mtime = stat.mtime.sec
      newest = { name = name, type = typ }
    end
  end
  return newest
end

local function refresh_codex(cwd)
  local ok = pcall(function()
    local base = vim.fn.expand("~/.codex/sessions")
    if vim.fn.isdirectory(base) ~= 1 then
      set("Codex", 0)
      return
    end
    -- YYYY -> MM -> DD, cada nivel se busca el más reciente por mtime.
    local dir = base
    for _ = 1, 3 do
      local e = newest_entry(dir)
      if not e or e.type ~= "directory" then
        set("Codex", 0)
        return
      end
      dir = dir .. "/" .. e.name
    end
    local e = newest_entry(dir)
    if not e or e.type ~= "file" then
      set("Codex", 0)
      return
    end
    local path = dir .. "/" .. e.name

    local session_cwd, total_tokens = nil, 0
    local f = io.open(path, "r")
    if f then
      for line in f:lines() do
        if line ~= "" then
          local decoded_ok, d = pcall(vim.json.decode, line)
          if decoded_ok then
            if d.type == "session_meta" and d.payload then
              session_cwd = d.payload.cwd
            elseif d.payload and d.payload.type == "token_count" and d.payload.info and d.payload.info.total_token_usage then
              total_tokens = d.payload.info.total_token_usage.total_tokens or 0
            end
          end
        end
      end
      f:close()
    end

    if session_cwd ~= cwd then
      set("Codex", 0)
      return
    end
    set("Codex", total_tokens, estimate_cost(total_tokens, "codex"))
  end)
  if not ok then
    set("Codex", 0)
  end
end

-- ---------------------------------------------------------------------
-- OpenCode: sqlite ~/.local/share/opencode/opencode.db, tabla `session`
-- -- ya trae `cost` en USD calculado por el proveedor, no hay que estimar.
-- ---------------------------------------------------------------------
local function refresh_opencode(cwd)
  local db = vim.fn.expand("~/.local/share/opencode/opencode.db")
  if vim.fn.filereadable(db) ~= 1 then
    set("OpenCode", 0)
    return
  end
  local sql = string.format(
    "SELECT tokens_input+tokens_output+tokens_reasoning+tokens_cache_read+tokens_cache_write, cost "
      .. "FROM session WHERE directory = %s ORDER BY time_updated DESC LIMIT 1;",
    vim.fn.shellescape(cwd)
  )
  vim.system({ "sqlite3", "-separator", "|", db, sql }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 or not res.stdout or vim.trim(res.stdout) == "" then
        set("OpenCode", 0)
        return
      end
      local tokens, cost = res.stdout:match("(%d+)|([%d%.]+)")
      set("OpenCode", tonumber(tokens) or 0, tonumber(cost), true)
    end)
  end)
end

-- ---------------------------------------------------------------------
-- Gemini CLI: ~/.gemini/tmp/<basename(cwd) en minúscula>/chats/**/*.jsonl
-- -- se suma tokens.total de cada línea type=="gemini" del .jsonl de chat
-- modificado más reciente.
-- ---------------------------------------------------------------------
local function refresh_gemini(cwd)
  local ok = pcall(function()
    local project_key = vim.fn.fnamemodify(cwd, ":t"):lower()
    local chats_dir = vim.fn.expand("~/.gemini/tmp/") .. project_key .. "/chats"
    if vim.fn.isdirectory(chats_dir) ~= 1 then
      set("Gemini", 0)
      return
    end

    -- chats/<sessionUuid>/<msgUuid>.jsonl -- el subdir de sesión más
    -- reciente, y dentro el archivo más reciente.
    local session_entry = newest_entry(chats_dir)
    if not session_entry or session_entry.type ~= "directory" then
      set("Gemini", 0)
      return
    end
    local session_dir = chats_dir .. "/" .. session_entry.name
    local file_entry = newest_entry(session_dir)
    if not file_entry or file_entry.type ~= "file" then
      set("Gemini", 0)
      return
    end

    local tokens = 0
    local f = io.open(session_dir .. "/" .. file_entry.name, "r")
    if f then
      for line in f:lines() do
        if line ~= "" then
          local decoded_ok, d = pcall(vim.json.decode, line)
          if decoded_ok and d.type == "gemini" and d.tokens then
            tokens = tokens + (d.tokens.total or 0)
          end
        end
      end
      f:close()
    end

    set("Gemini", tokens, estimate_cost(tokens, "gemini"))
  end)
  if not ok then
    set("Gemini", 0)
  end
end

-- ---------------------------------------------------------------------
-- Copilot CLI: sqlite ~/.copilot/session-store.db -- sessions.cwd +
-- assistant_usage_events (input/output/cache tokens por turno).
-- ---------------------------------------------------------------------
local function refresh_copilot_cli(cwd)
  local db = vim.fn.expand("~/.copilot/session-store.db")
  if vim.fn.filereadable(db) ~= 1 then
    set("Copilot", 0)
    return
  end
  local sql = string.format(
    "SELECT SUM(input_tokens+output_tokens+COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0)) "
      .. "FROM assistant_usage_events WHERE session_id = ("
      .. "SELECT id FROM sessions WHERE cwd = %s ORDER BY updated_at DESC LIMIT 1);",
    vim.fn.shellescape(cwd)
  )
  vim.system({ "sqlite3", db, sql }, { text = true }, function(res)
    vim.schedule(function()
      local tokens = res.code == 0 and tonumber(vim.trim(res.stdout or "")) or nil
      set("Copilot", tokens or 0, estimate_cost(tokens or 0, "copilot"))
    end)
  end)
end

function M.refresh()
  local cwd = vim.fn.getcwd()
  refresh_claude(cwd)
  refresh_codex(cwd)
  refresh_opencode(cwd)
  refresh_gemini(cwd)
  refresh_copilot_cli(cwd)
end

--- { tokens, cost, cost_is_estimate } agregado de todos los agentes con
--- actividad en la carpeta actual.
function M.total()
  local tokens, cost, any_estimate, any_cost = 0, 0, false, false
  for _, d in pairs(M.data) do
    tokens = tokens + d.tokens
    if d.cost then
      cost = cost + d.cost
      any_cost = true
      if not d.exact_cost then
        any_estimate = true
      end
    end
  end
  return { tokens = tokens, cost = any_cost and cost or nil, is_estimate = any_estimate }
end

function M.start(interval_ms)
  M.refresh()
  local timer = vim.uv.new_timer()
  timer:start(2000, interval_ms or 15000, vim.schedule_wrap(M.refresh))
  vim.api.nvim_create_autocmd("DirChanged", {
    group = vim.api.nvim_create_augroup("AgentUsageWatch", { clear = true }),
    callback = M.refresh,
  })
end

return M
