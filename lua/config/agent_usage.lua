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
  quotas = {}, -- name -> { session_remaining, session_reset, weekly_remaining, weekly_reset }
  quota_alerts = {},
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
  M.refresh_quotas()
  if M.active_quota_agent == "Codex" then M.refresh_codex_quota() end
end

function M.activate_quota_monitor(name)
  M.active_quota_agent = name
  if name == "Codex" then M.refresh_codex_quota() end
  M.refresh_quotas()
end

-- Codex y Claude muestran la cuota de suscripción en sus propias terminales,
-- no en sus archivos de sesión. Se leen las últimas líneas ya renderizadas:
-- nunca se consultan credenciales ni se hacen peticiones de red.
function M.refresh_quotas()
  local codex, claude
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buftype == "terminal" then
      local line_count = vim.api.nvim_buf_line_count(buf)
      local lines = vim.api.nvim_buf_get_lines(buf, math.max(0, line_count - 250), -1, false)
      local text = table.concat(lines, "\n")
      if text:find("OpenAI Codex", 1, true) then
        local session_remaining, session_reset = text:match("5h limit:%s*(%d+)%% left%s*%(resets%s*([^%)]+)%)")
        local weekly_remaining, weekly_reset = text:match("Weekly limit:%s*(%d+)%% left%s*%(resets%s*([^%)]+)%)")
        if session_remaining or weekly_remaining then
          codex = { session_remaining = tonumber(session_remaining), session_reset = session_reset,
            weekly_remaining = tonumber(weekly_remaining), weekly_reset = weekly_reset }
        end
      end
      if text:find("Current week (all models)", 1, true) then
        local session_used = text:match("Current session.-(%d+)%% used")
        local weekly_used, weekly_reset = text:match("Current week %(all models%).-(%d+)%% used%s*Resets%s+([^\n]+)")
        if session_used or weekly_used then
          claude = { session_remaining = 100 - (tonumber(session_used) or 0),
            weekly_remaining = 100 - (tonumber(weekly_used) or 0), weekly_reset = weekly_reset }
        end
      end
    end
  end
  local snapshot = vim.fn.getcwd() .. "/.claude/usage_limits.json"
  local stream = io.open(snapshot, "r")
  if stream then
    local ok, limits = pcall(vim.json.decode, stream:read("*a"))
    stream:close()
    if ok and type(limits) == "table" then
      local five_hour = type(limits.five_hour) == "table" and limits.five_hour or {}
      local seven_day = type(limits.seven_day) == "table" and limits.seven_day or {}
      claude = {
        session_remaining = five_hour.used_percentage and 100 - five_hour.used_percentage or nil,
        session_reset = five_hour.resets_at and os.date("%H:%M", five_hour.resets_at) or nil,
        weekly_remaining = seven_day.used_percentage and 100 - seven_day.used_percentage or nil,
        weekly_reset = seven_day.resets_at and os.date("%d %b %H:%M", seven_day.resets_at) or nil,
      }
    end
  end
  if codex then M.quotas.Codex = codex end
  if claude then
    M.quotas["Claude Code"] = claude
    if M.active_quota_agent == "Claude Code" then M.notify_quota("Claude Code", claude) end
  end
end

function M.notify_quota(name, quota)
  local used = 100 - (quota.session_remaining or 100)
  local level = used >= 95 and "critical" or used >= 80 and "warning" or nil
  if not level then
    M.quota_alerts[name] = nil
    return
  end
  if M.quota_alerts[name] == level then return end
  M.quota_alerts[name] = level
  local reset = quota.session_reset and (" · reinicia " .. quota.session_reset) or ""
  vim.notify(string.format("%s: %d%% de la ventana de 5h usado%s", name, used, reset),
    level == "critical" and vim.log.levels.ERROR or vim.log.levels.WARN,
    { title = level == "critical" and "󰅙 Límite casi agotado" or "󰀦 Uso elevado", timeout = 8000 })
end

function M.refresh_codex_quota()
  local now = os.time()
  if M.codex_quota_refreshed_at and now - M.codex_quota_refreshed_at < 300 then return end
  if M.codex_quota_pending then return end
  M.codex_quota_pending = true
  local job
  local function save_limits(limits)
    if type(limits) ~= "table" then return end
    local primary = type(limits.primary) == "table" and limits.primary or {}
    local secondary = type(limits.secondary) == "table" and limits.secondary or {}
            M.quotas.Codex = {
      session_remaining = primary.usedPercent and 100 - primary.usedPercent or nil,
      session_reset = primary.resetsAt and os.date("%H:%M", primary.resetsAt) or nil,
      weekly_remaining = secondary.usedPercent and 100 - secondary.usedPercent or nil,
      weekly_reset = secondary.resetsAt and os.date("%d %b %H:%M", secondary.resetsAt) or nil,
            }
            M.notify_quota("Codex", M.quotas.Codex)
    M.codex_quota_refreshed_at = os.time()
    M.codex_quota_pending = false
    pcall(vim.cmd.redrawtabline)
    if job then vim.fn.jobstop(job) end
  end
  job = vim.fn.jobstart({ "codex", "app-server", "--stdio" }, {
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        local ok, response = pcall(vim.json.decode, line)
        local limits = type(response) == "table"
          and response.id == 2
          and type(response.result) == "table"
          and response.result.rateLimits
        if type(limits) == "table" then save_limits(limits) end
      end
    end,
    on_exit = function()
      vim.schedule(function() M.codex_quota_pending = false end)
    end,
  })
  if job <= 0 then
    M.codex_quota_pending = false
    return
  end
  vim.fn.chansend(job, table.concat({
    vim.json.encode({ id = 1, method = "initialize", params = { clientInfo = { name = "vim-usage", version = "1.0" } } }),
    vim.json.encode({ method = "initialized", params = {} }),
    vim.json.encode({ id = 2, method = "account/rateLimits/read", params = vim.NIL }),
  }, "\n") .. "\n")
end

function M.quota_summary()
  local parts = {}
  local function add(name, quota)
    if not quota then return end
    local text = name
    if quota.session_remaining then
      text = text .. string.format(" 5h %d%%", 100 - quota.session_remaining)
      if quota.session_reset then text = text .. " → " .. quota.session_reset end
    end
    if quota.weekly_remaining then
      text = text .. string.format(" · 7d %d%%", 100 - quota.weekly_remaining)
      if quota.weekly_reset then text = text .. " → " .. quota.weekly_reset end
    end
    local usage_name = name == "Claude" and "Claude Code" or name
    local tokens = (M.data[usage_name] or {}).tokens or 0
    if tokens > 0 then
      local amount = tokens >= 1000000 and string.format("%.1fM", tokens / 1000000)
        or tokens >= 1000 and string.format("%.1fK", tokens / 1000) or tostring(tokens)
      text = text .. " · " .. amount .. " tok"
    end
    table.insert(parts, text)
  end
  if not M.active_quota_agent or M.active_quota_agent == "Codex" then add("Codex", M.quotas.Codex) end
  if not M.active_quota_agent or M.active_quota_agent == "Claude Code" then add("Claude", M.quotas["Claude Code"]) end
  return #parts > 0 and table.concat(parts, "  |  ") or nil
end

function M.session_summary()
  local parts = {}
  local names = { "Claude Code", "Codex", "OpenCode", "Gemini", "Copilot" }
  local labels = { ["Claude Code"] = "Claude", Codex = "Codex", OpenCode = "OpenCode", Gemini = "Gemini", Copilot = "Copilot" }
  for _, name in ipairs(names) do
    local tokens = (M.data[name] or {}).tokens or 0
    if (not M.active_quota_agent or name == M.active_quota_agent)
      and tokens > 0 and not ((name == "Codex" and M.quotas.Codex) or (name == "Claude Code" and M.quotas[name])) then
      local amount = tokens >= 1000000 and string.format("%.1fM", tokens / 1000000)
        or tokens >= 1000 and string.format("%.1fK", tokens / 1000) or tostring(tokens)
      table.insert(parts, labels[name] .. " " .. amount .. " tok")
    end
  end
  return #parts > 0 and table.concat(parts, "  |  ") or nil
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

local started_timer = nil

-- Idempotente: si el spec de bufferline se re-configura (:Lazy reload, hot
-- reload al editar plugins/editor.lua) sin esta guarda quedaba un timer
-- viejo corriendo por cada llamada, acumulando polls de fondo.
function M.start(interval_ms)
  if started_timer then
    return started_timer
  end
  M.refresh()
  local timer = vim.uv.new_timer()
  timer:start(2000, interval_ms or 15000, vim.schedule_wrap(M.refresh))
  vim.api.nvim_create_autocmd("DirChanged", {
    group = vim.api.nvim_create_augroup("AgentUsageWatch", { clear = true }),
    callback = M.refresh,
  })
  started_timer = timer
  return timer
end

return M
