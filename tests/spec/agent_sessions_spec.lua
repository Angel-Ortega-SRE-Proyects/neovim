local h = require("tests.spec_helpers")
local util = require("config.agent_sessions.util")
local sessions = require("config.agent_sessions")

local original_home = vim.env.HOME
local original_path = vim.env.PATH
local home

local function iso(epoch)
  return os.date("!%Y-%m-%dT%H:%M:%S.000Z", epoch)
end

--- Envejece un archivo/carpeta para que su última actividad quede en el pasado.
local function age(path, seconds)
  vim.fn.system({ "touch", "-d", "@" .. (os.time() - seconds), path })
end

--- CLI falsa que registra sus argumentos en `<bin>/<name>.args` y sale con 0.
local function recording_cli(bin, name)
  local path = bin .. "/" .. name
  h.write(path, { "#!/bin/sh", 'echo "$@" > "$0.args"' })
  vim.fn.setfperm(path, "rwxr-xr-x")
  return path .. ".args"
end

--- HOME falso y limpio por test; se llama dentro de cada describe.
local function sandbox()
  before_each(function()
    home = h.tempdir()
    vim.env.HOME = home
    sessions.invalidate()
  end)
  after_each(function()
    vim.env.HOME = original_home
    vim.env.PATH = original_path
    sessions.invalidate()
    h.cleanup()
  end)
end

describe("utilidades de sesiones", function()
  sandbox()
  it("clasifica el estado por antigüedad de la última actividad", function()
    assert.equals("ejecutando", util.time_status(os.time()))
    assert.equals("activo", util.time_status(os.time() - 60))
    assert.equals("detenido", util.time_status(os.time() - util.ACTIVE_WINDOW - 1))
    assert.equals("detenido", util.time_status(0))
  end)

  it("convierte fechas ISO UTC y descarta prompts inyectados", function()
    assert.equals(1767225600, util.iso_to_epoch("2026-01-01T00:00:00Z"))
    assert.equals(0, util.iso_to_epoch(nil))
    assert.is_false(util.is_user_prompt("<system-reminder>x"))
    assert.is_false(util.is_user_prompt("# AGENTS.md instrucciones"))
    assert.is_true(util.is_user_prompt("arregla el bug"))
    assert.equals("hola", util.prompt_from_content({ { text = "<ctx>" }, { text = "hola" } }))
  end)

  it("recorta títulos largos respetando caracteres multibyte", function()
    local title = util.compact_title(string.rep("á", 60), "x")
    assert.equals(52, vim.fn.strchars(title))
    assert.matches("%.%.%.$", title)
    assert.equals("x", util.compact_title("   ", "x"))
  end)

  it("cached relee solo cuando cambia el archivo", function()
    local path = home .. "/f.txt"
    h.write(path, "a")
    local reads = 0
    local reader = function() reads = reads + 1 return reads end
    util.cached(path, reader)
    util.cached(path, reader)
    assert.equals(1, reads)
    h.write(path, "abc")
    util.cached(path, reader)
    assert.equals(2, reads)
  end)

  it("session() construye la entrada estándar del hub", function()
    local entry = util.session({
      kind = "Grok", label = "Grok", id = "1234-5678-90ab-cdef", title = "Hola",
      cwd = "/tmp/", cmd = { "grok" }, path = "/p", updated_at = 5,
    })
    assert.equals("Grok · Hola [90abcdef]", entry.name)
    assert.equals("/tmp", entry.cwd)
    assert.is_true(entry.external)
    assert.equals("agent", entry.action)
  end)
end)

describe("proveedor Claude Code", function()
  sandbox()
  local claude = require("config.agent_sessions.claude")

  local function fixture(id, cwd)
    h.write(home .. "/.claude/projects/-demo/" .. id .. ".jsonl", h.jsonl({
      { type = "user", isMeta = true, cwd = cwd, sessionId = id, message = { content = "<local-command-caveat>" } },
      { type = "user", isSidechain = true, cwd = cwd, sessionId = id, message = { content = "subagente" } },
      { type = "user", cwd = cwd, sessionId = id, message = { content = { { type = "text", text = "revisa el hub" } } } },
    }))
  end

  it("lista sesiones con el primer prompt real y el comando de reanudar", function()
    fixture("abc", "/tmp/demo")
    local list = claude.list()
    assert.equals(1, #list)
    assert.matches("^Claude · revisa el hub", list[1].name)
    assert.same({ "claude", "--resume", "abc" }, list[1].cmd)
    assert.equals("/tmp/demo", list[1].cwd)
  end)

  it("usa el registro de procesos vivos: busy = ejecutando, idle = activo", function()
    fixture("vivo", "/tmp/demo")
    fixture("muerto", "/tmp/demo")
    h.write(home .. "/.claude/sessions/1.json", vim.json.encode({ pid = vim.fn.getpid(), sessionId = "vivo", status = "busy" }))
    local by_id = {}
    for _, entry in ipairs(claude.list()) do by_id[entry.session_id] = entry end
    claude.invalidate()
    assert.equals("ejecutando", claude.status(by_id.vivo))
    assert.equals("detenido", claude.status(by_id.muerto))

    h.write(home .. "/.claude/sessions/1.json", vim.json.encode({ pid = vim.fn.getpid(), sessionId = "vivo", status = "idle" }))
    claude.invalidate()
    assert.equals("activo", claude.status(by_id.vivo))

    h.write(home .. "/.claude/sessions/1.json", vim.json.encode({ pid = 999999999, sessionId = "vivo", status = "busy" }))
    claude.invalidate()
    assert.equals("detenido", claude.status(by_id.vivo))
  end)

  it("sin registro de procesos cae al estado por antigüedad", function()
    fixture("abc", "/tmp/demo")
    assert.equals("ejecutando", claude.status(claude.list()[1]))
  end)

  it("remove borra el archivo de la sesión", function()
    fixture("abc", "/tmp/demo")
    local entry = claude.list()[1]
    assert.is_true(claude.remove(entry))
    assert.equals(0, vim.fn.filereadable(entry.path))
  end)
end)

describe("proveedor Codex", function()
  sandbox()
  local codex = require("config.codex_sessions")

  local function fixture(id, source, text)
    local path = home .. "/.codex/sessions/2026/09/28/" .. id .. ".jsonl"
    h.write(path, h.jsonl({
      { type = "session_meta", payload = { id = id, cwd = "/tmp/demo", source = source } },
      { type = "response_item", payload = { role = "user", content = { { type = "input_text", text = "# AGENTS.md" } } } },
      { type = "response_item", payload = { role = "user", content = { { type = "input_text", text = text } } } },
    }))
    return path
  end

  it("lista sesiones interactivas y descarta subagentes", function()
    fixture("aaaa-1111", "cli", "arregla el login")
    fixture("bbbb-2222", { subagent = { depth = 1 } }, "subtarea")
    local list = codex.list()
    assert.equals(1, #list)
    assert.equals("Codex · arregla el login [aaa-1111]", list[1].name)
    assert.same({ "codex", "resume", "aaaa-1111" }, list[1].cmd)
  end)

  it("estado según el lock de escritura y la antigüedad", function()
    local path = fixture("aaaa-1111", "cli", "x")
    h.write(home .. "/.codex/thread-writer-locks/aaaa-1111.lock", "")
    assert.equals("ejecutando", codex.status(codex.list()[1]))

    age(path, 3600)
    age(home .. "/.codex/thread-writer-locks/aaaa-1111.lock", 3600)
    assert.equals("detenido", codex.status(codex.list()[1]))
    age(home .. "/.codex/thread-writer-locks/aaaa-1111.lock", 60)
    assert.equals("activo", codex.status(codex.list()[1]))
  end)
end)

describe("proveedor OpenCode", function()
  sandbox()
  local opencode = require("config.agent_sessions.opencode")

  local function database(rows)
    local db = home .. "/.local/share/opencode/opencode.db"
    vim.fn.mkdir(vim.fn.fnamemodify(db, ":h"), "p")
    local sql = { "create table session (id text, title text, directory text, parent_id text,"
      .. " time_updated integer, time_archived integer);" }
    for _, row in ipairs(rows) do
      table.insert(sql, string.format("insert into session values ('%s','%s','%s',%s,%d,%s);",
        row.id, row.title, row.directory, row.parent or "null", row.updated * 1000, row.archived or "null"))
    end
    vim.fn.system({ "sqlite3", db, table.concat(sql, " ") })
    assert.equals(0, vim.v.shell_error)
  end

  it("lista sesiones raíz no archivadas desde SQLite", function()
    database({
      { id = "ses_1", title = "Refactor", directory = "/tmp/demo", updated = os.time() },
      { id = "ses_hijo", title = "Hijo", directory = "/tmp/demo", updated = os.time(), parent = "'ses_1'" },
      { id = "ses_arch", title = "Viejo", directory = "/tmp/demo", updated = os.time(), archived = 1 },
    })
    local list = opencode.list()
    assert.equals(1, #list)
    assert.equals("OpenCode · Refactor [ses_1]", list[1].name)
    assert.same({ "opencode", "-s", "ses_1" }, list[1].cmd)
    assert.equals("ejecutando", opencode.status(list[1]))
  end)

  it("remove delega en `opencode session delete`", function()
    database({ { id = "ses_1", title = "T", directory = "/tmp/demo", updated = 1 } })
    local bin = h.tempdir()
    local args = recording_cli(bin, "opencode")
    vim.env.PATH = bin .. ":" .. original_path
    assert.is_true(opencode.remove(opencode.list()[1]))
    assert.same({ "session delete ses_1" }, vim.fn.readfile(args))
  end)
end)

describe("proveedor Gemini", function()
  sandbox()
  local gemini = require("config.agent_sessions.gemini")

  it("lista chats interactivos con la raíz del proyecto y omite el servidor A2A", function()
    local project = home .. "/.gemini/tmp/demo"
    h.write(project .. "/.project_root", "/tmp/demo")
    h.write(project .. "/chats/session-1.jsonl", h.jsonl({
      { sessionId = "3cf5c5cd-20ee-4e4e", kind = "main" },
      { type = "user", content = { { text = "<session_context>..." } } },
      { type = "user", content = { { text = "elimina antigravity" } } },
    }))
    h.write(project .. "/chats/session-2.jsonl", h.jsonl({ { sessionId = "a2a-server", kind = "main" } }))
    local list = gemini.list()
    assert.equals(1, #list)
    assert.matches("^Gemini · elimina antigravity", list[1].name)
    assert.equals("/tmp/demo", list[1].cwd)
    assert.same({ "gemini", "--resume", "3cf5c5cd-20ee-4e4e" }, list[1].cmd)
    assert.is_true(gemini.remove(list[1]))
    assert.same({}, gemini.list())
  end)

  it("lee títulos en el formato con $set.messages", function()
    local project = home .. "/.gemini/tmp/demo"
    h.write(project .. "/.project_root", "/tmp/demo")
    h.write(project .. "/chats/session-1.jsonl", h.jsonl({
      { sessionId = "aaaa-bbbb", kind = "main" },
      { ["$set"] = { messages = { { type = "user", content = { { text = "desde set" } } } } } },
    }))
    assert.matches("desde set", gemini.list()[1].name)
  end)
end)

describe("proveedor Copilot", function()
  sandbox()
  local copilot = require("config.agent_sessions.copilot")

  local function fixture(id, extra)
    local dir = home .. "/.copilot/session-state/" .. id
    h.write(dir .. "/workspace.yaml", vim.list_extend({ "id: " .. id, "cwd: /tmp/demo", "summary: |-" }, extra or {}))
    h.write(dir .. "/events.jsonl", h.jsonl({
      { type = "session.start", data = {} },
      { type = "user.message", data = { content = "puede ver los hooks ?" } },
    }))
    return dir
  end

  it("usa el primer mensaje como título, o el nombre si existe", function()
    fixture("4420c2ff-b2b5")
    fixture("5555aaaa-0000", { "name: sesión con nombre" })
    local by_id = {}
    for _, entry in ipairs(copilot.list()) do by_id[entry.session_id] = entry end
    assert.matches("puede ver los hooks", by_id["4420c2ff-b2b5"].name)
    assert.matches("sesión con nombre", by_id["5555aaaa-0000"].name)
    assert.same({ "copilot", "--resume=4420c2ff-b2b5" }, by_id["4420c2ff-b2b5"].cmd)
  end)

  it("working en open-sessions-state = ejecutando; inactiva = detenido", function()
    local dir = fixture("4420c2ff-b2b5")
    h.write(home .. "/.copilot/open-sessions-state.json", vim.json.encode({ ["4420c2ff-b2b5"] = { working = true } }))
    assert.equals("ejecutando", copilot.status(copilot.list()[1]))
    h.write(home .. "/.copilot/open-sessions-state.json", vim.json.encode({ ["4420c2ff-b2b5"] = { working = false } }))
    assert.equals("activo", copilot.status(copilot.list()[1]))
    age(dir .. "/events.jsonl", 3600)
    assert.equals("detenido", copilot.status(copilot.list()[1]))
  end)

  it("remove borra la carpeta de la sesión", function()
    local dir = fixture("4420c2ff-b2b5")
    assert.is_true(copilot.remove(copilot.list()[1]))
    assert.equals(0, vim.fn.isdirectory(dir))
  end)
end)

describe("proveedor Grok", function()
  sandbox()
  local grok = require("config.agent_sessions.grok")

  local function fixture(id, summary, last_active)
    h.write(home .. "/.grok/sessions/x/" .. id .. "/summary.json", vim.json.encode({
      info = { id = id, cwd = "/tmp/demo" }, session_summary = summary, last_active_at = iso(last_active),
    }))
  end

  it("usa session_summary o, si falta, el primer prompt del historial", function()
    fixture("g-1", "Resumen propio", os.time())
    fixture("g-2", "", os.time())
    h.write(home .. "/.grok/sessions/x/prompt_history.jsonl", h.jsonl({
      { session_id = "g-2", prompt = "ls", is_bash = true },
      { session_id = "g-2", prompt = "hola grok", is_bash = false },
    }))
    local by_id = {}
    for _, entry in ipairs(grok.list()) do by_id[entry.session_id] = entry end
    assert.matches("Resumen propio", by_id["g-1"].name)
    assert.matches("hola grok", by_id["g-2"].name)
    assert.same({ "grok", "--resume", "g-1" }, by_id["g-1"].cmd)
  end)

  it("una sesión vieja figura activa si sigue en active_sessions.json", function()
    fixture("g-1", "x", os.time() - 3600)
    for _, file in ipairs(vim.fn.globpath(home .. "/.grok/sessions/x/g-1", "*", false, true)) do age(file, 3600) end
    age(home .. "/.grok/sessions/x/g-1", 3600)
    local entry = grok.list()[1]
    assert.equals("detenido", grok.status(entry))
    h.write(home .. "/.grok/active_sessions.json", vim.json.encode({ { id = "g-1" } }))
    assert.equals("activo", grok.status(entry))
  end)

  it("remove delega en `grok sessions delete`", function()
    fixture("g-1", "x", os.time())
    local bin = h.tempdir()
    local args = recording_cli(bin, "grok")
    vim.env.PATH = bin .. ":" .. original_path
    assert.is_true(grok.remove(grok.list()[1]))
    assert.same({ "sessions delete g-1" }, vim.fn.readfile(args))
  end)
end)

describe("agregador de sesiones", function()
  sandbox()
  local function claude_session(id, cwd)
    h.write(home .. "/.claude/projects/-demo/" .. id .. ".jsonl", h.jsonl({
      { type = "user", cwd = cwd, sessionId = id, message = { content = "prompt " .. id } },
    }))
  end

  it("solo activa proveedores cuya CLI está en PATH", function()
    local bin = h.tempdir()
    h.fake_cli(bin, "claude")
    h.fake_cli(bin, "grok")
    vim.env.PATH = bin
    local kinds = vim.tbl_map(function(provider) return provider.kind end, sessions.providers())
    assert.same({ "Claude Code", "Grok" }, kinds)
    assert.is_true(sessions.is_installed("claude"))
    assert.is_false(sessions.is_installed("codex"))
  end)

  it("ignora proveedores sin CLI aunque tengan datos en disco", function()
    claude_session("abc", "/tmp/demo")
    vim.env.PATH = h.tempdir()
    assert.same({}, sessions.list())
  end)

  it("ordena por actividad, agrupa por carpeta y cachea el listado", function()
    local bin = h.tempdir()
    h.fake_cli(bin, "claude")
    vim.env.PATH = bin .. ":" .. original_path
    claude_session("viejo", "/tmp/a")
    age(home .. "/.claude/projects/-demo/viejo.jsonl", 600)
    claude_session("nuevo", "/tmp/b")
    claude_session("otro", "/tmp/a")
    age(home .. "/.claude/projects/-demo/otro.jsonl", 60)

    local ids = vim.tbl_map(function(entry) return entry.session_id end,
      vim.tbl_filter(function(entry) return entry.kind == "Claude Code" end, sessions.list()))
    assert.same({ "nuevo", "otro", "viejo" }, ids)

    local groups = {}
    for _, group in ipairs(sessions.grouped()) do
      if group.path == "/tmp/a" or group.path == "/tmp/b" then table.insert(groups, group) end
    end
    assert.equals("/tmp/b", groups[1].path)
    assert.equals(2, #groups[2].sessions)

    claude_session("recien", "/tmp/c")
    assert.is_nil(vim.tbl_filter(function(entry) return entry.session_id == "recien" end, sessions.list())[1])
    sessions.invalidate()
    assert.is_not_nil(vim.tbl_filter(function(entry) return entry.session_id == "recien" end, sessions.list())[1])
  end)

  it("status y remove despachan al proveedor de cada sesión", function()
    local bin = h.tempdir()
    h.fake_cli(bin, "claude")
    vim.env.PATH = bin .. ":" .. original_path
    claude_session("abc", "/tmp/demo")
    local entry = vim.tbl_filter(function(item) return item.kind == "Claude Code" end, sessions.list())[1]
    assert.equals("ejecutando", sessions.status(entry))
    assert.is_true(sessions.remove(entry))
    assert.equals(0, vim.fn.filereadable(entry.path))
  end)

  it("status tiene un valor por defecto para tipos desconocidos", function()
    assert.equals("activo", sessions.status({ kind = "Otro", active = true }))
    assert.equals("detenido", sessions.status({ kind = "Otro" }))
    assert.is_false(sessions.remove({ kind = "Otro" }))
  end)
end)
