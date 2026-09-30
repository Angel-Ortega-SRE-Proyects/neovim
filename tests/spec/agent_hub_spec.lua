local h = require("tests.spec_helpers")

-- Entorno controlado ANTES de cargar ai_cli: solo claude, copilot y grok
-- "instalados" (scripts que duermen) y un HOME sin sesiones reales.
local bin = h.tempdir()
for _, name in ipairs({ "claude", "copilot", "grok" }) do h.fake_cli(bin, name) end
local original_path = vim.env.PATH
vim.env.PATH = bin .. ":/usr/bin:/bin"
local home = h.tempdir()
vim.env.HOME = home
vim.fn.mkdir(home .. "/.claude/sessions", "p")

local projects = require("config.projects")
local agent_sessions = require("config.agent_sessions")
require("plugins.ai_cli")
local state = _G.__agent_hub_state
local original_cwd = vim.fn.getcwd()

local function find_buf(filetype)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == filetype
        and #vim.fn.win_findbuf(buf) > 0 then
      return buf
    end
  end
end

local function focus(buf)
  local win = vim.fn.win_findbuf(buf)[1]
  assert(win, "el buffer no está visible")
  vim.api.nvim_set_current_win(win)
  return win
end

local function goto_line(buf, text)
  local win = focus(buf)
  local line = h.find_line(buf, text)
  assert(line, "no se encontró: " .. text .. "\n" .. table.concat(h.lines(buf), "\n"))
  vim.api.nvim_win_set_cursor(win, { line, 0 })
  return line
end

local function press(buf, lhs)
  focus(buf)
  vim.cmd("stopinsert")
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if map.lhs == lhs or map.lhs == vim.api.nvim_replace_termcodes(lhs, true, false, true) then
      return map.callback()
    end
  end
  error("sin mapping " .. lhs)
end

local function open_hub()
  vim.cmd("Agents")
  return find_buf("agent-hub"), find_buf("agent-changes")
end

local function project_dir()
  local dir = h.git_repo({ ["src/app.lua"] = "print(1)", ["README.md"] = "hola" })
  projects.record(dir)
  vim.cmd("cd " .. dir)
  return dir
end

local function kill_all()
  for name, session in pairs(state) do
    if session.buf and vim.api.nvim_buf_is_valid(session.buf) and vim.b[session.buf].terminal_job_id then
      pcall(vim.fn.jobstop, vim.b[session.buf].terminal_job_id)
    end
    state[name] = nil
  end
end

local function reset()
  pcall(vim.cmd, "AgentHubClose")
  kill_all()
  vim.cmd("cd " .. original_cwd)
  os.remove(vim.fn.stdpath("state") .. "/projects.json")
  vim.fn.delete(home .. "/.claude/projects", "rf")
  agent_sessions.invalidate()
  h.reset_ui()
end

describe("AgentHub: comandos y agentes instalados", function()
  after_each(reset)

  it("registra todos los comandos, abreviaturas y atajos", function()
    for _, command in ipairs({ "Claude", "Codex", "OpenCode", "Gemini", "CopilotCli", "Grok", "Agents",
      "AgentWorkspace", "AgentDiff", "AgentKill", "AgentsKillAll", "AgentHubClose" }) do
      assert.equals(2, vim.fn.exists(":" .. command), command)
    end
    assert.equals("Grok", vim.fn.maparg("grok", "c", true))
    assert.equals("CopilotCli", vim.fn.maparg("copilotcli", "c", true))
    assert.is_function(vim.fn.maparg(" aa", "n", false, true).callback)
  end)

  it("NUEVA INSTANCIA solo ofrece las CLIs instaladas", function()
    local sidebar = open_hub()
    local lines = table.concat(h.lines(sidebar), "\n")
    assert.matches("%+ Claude Code", lines)
    assert.matches("%+ Copilot", lines)
    assert.matches("%+ Grok", lines)
    assert.is_nil(lines:find("+ Codex", 1, true))
    assert.is_nil(lines:find("+ Gemini", 1, true))
    assert.is_nil(lines:find("+ OpenCode", 1, true))
  end)

  it("desactiva Espacio+e dentro de AgentHub", function()
    local sidebar = open_hub()
    focus(sidebar)
    assert.equals("<Nop>", vim.fn.maparg(" e", "n", false, true).rhs)
  end)
end)

describe("AgentHub: ciclo de vida de un agente", function()
  after_each(reset)

  it(":CopilotCli arranca en flotante, se oculta y :AgentKill lo detiene", function()
    local dir = project_dir()
    vim.cmd("CopilotCli")
    local session = state.Copilot
    assert.is_not_nil(session)
    assert.equals(dir, session.cwd)
    assert.equals("terminal", vim.bo[session.buf].buftype)
    assert.equals(1, require("config.agents_status").visible)

    vim.cmd("CopilotCli")
    assert.is_nil(session.win)
    assert.equals(1, require("config.agents_status").hidden)

    vim.cmd("AgentKill Copilot")
    assert.is_nil(state.Copilot)
    assert.is_false(vim.api.nvim_buf_is_valid(session.buf))
  end)

  it(":Claude pide la carpeta y :AgentsKillAll detiene todo", function()
    local dir = project_dir()
    h.stub(vim.fn, "input", function() return dir end, function()
      vim.cmd("Claude")
    end)
    vim.cmd("CopilotCli")
    assert.is_not_nil(state["Claude Code"])
    assert.equals(dir .. "/", state["Claude Code"].cwd)
    h.capture_notify(function() vim.cmd("AgentsKillAll") end)
    assert.same({}, vim.tbl_keys(state))
  end)

  it("cuando el proceso termina, la sesión se limpia sola", function()
    project_dir()
    vim.cmd("CopilotCli")
    local buf = state.Copilot.buf
    vim.fn.jobstop(vim.b[buf].terminal_job_id)
    assert.is_true(h.wait_for(function() return state.Copilot == nil end))
  end)

  it("no deja autocomandos WinClosed huérfanos al detener agentes", function()
    project_dir()
    -- Un WinClosed previo purga autocomandos de sesiones de tests anteriores.
    vim.cmd("split")
    vim.cmd("close")
    local baseline = #vim.api.nvim_get_autocmds({ event = "WinClosed" })
    vim.cmd("CopilotCli")
    local session = state.Copilot
    assert.is_not_nil(session)
    assert.equals(baseline + 1, #vim.api.nvim_get_autocmds({ event = "WinClosed" }))
    vim.cmd("AgentKill Copilot")
    vim.cmd("split")
    vim.cmd("close")
    assert.equals(baseline, #vim.api.nvim_get_autocmds({ event = "WinClosed" }))
  end)
end)

describe("AgentHub: vistas de proyecto y sesiones", function()
  after_each(reset)

  local function open_project_agents(dir)
    local sidebar = open_hub()
    goto_line(sidebar, vim.fn.fnamemodify(dir, ":t"))
    press(sidebar, "<CR>")
    assert.is_not_nil(h.find_line(sidebar, "PROYECTO"))
    goto_line(sidebar, "Ver agentes del proyecto")
    press(sidebar, "<CR>")
    assert.is_not_nil(h.find_line(sidebar, "AGENTES DEL PROYECTO"))
    return sidebar
  end

  local function claude_session(dir, id)
    h.write(home .. "/.claude/projects/-p/" .. id .. ".jsonl", h.jsonl({
      { type = "user", cwd = dir, sessionId = id, message = { content = "arregla el hub" } },
    }))
    agent_sessions.invalidate()
  end

  it("abre una sola pestaña con sidebar, agente, cambios y acciones", function()
    local dir = project_dir()
    local sidebar = open_hub()
    assert.is_true(vim.t.agent_hub)
    assert.equals(4, #vim.api.nvim_tabpage_list_wins(0))
    assert.is_not_nil(h.find_line(sidebar, "PROYECTOS REGISTRADOS"))
    assert.is_not_nil(h.find_line(sidebar, vim.fn.fnamemodify(dir, ":t")))
    vim.cmd("tabfirst")
    vim.cmd("Agents")
    assert.equals(2, #vim.api.nvim_list_tabpages())
    press(sidebar, "q")
    assert.equals(1, #vim.api.nvim_list_tabpages())
  end)

  it("lista sesiones externas del proyecto con su tipo en el hover", function()
    local dir = project_dir()
    claude_session(dir, "abc-123")
    local sidebar = open_project_agents(dir)
    assert.is_not_nil(h.find_line(sidebar, "AGENTES REGISTRADOS"))
    goto_line(sidebar, " Claude ")
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = sidebar })
    local hover
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
      if name:match("Agent Hub Hover") then hover = vim.api.nvim_win_get_buf(win) end
    end
    assert.is_not_nil(hover)
    assert.equals("Sesión Claude Code", h.lines(hover)[1])
    assert.is_not_nil(h.find_line(hover, "ID: abc-123"))
  end)

  it("Enter reanuda la sesión externa en el panel del agente", function()
    local dir = project_dir()
    claude_session(dir, "abc-123")
    local sidebar = open_project_agents(dir)
    goto_line(sidebar, " Claude ")
    press(sidebar, "<CR>")
    local name = "Claude · arregla el hub [abc123]"
    assert.is_not_nil(state[name], vim.inspect(vim.tbl_keys(state)))
    assert.is_true(state[name].external)
    assert.same({ "claude", "--resume", "abc-123" }, state[name].cmd)
    assert.equals(state[name].buf, vim.api.nvim_get_current_buf())
  end)

  it("d elimina una sesión externa tras confirmar", function()
    local dir = project_dir()
    claude_session(dir, "abc-123")
    local sidebar = open_project_agents(dir)
    goto_line(sidebar, " Claude ")
    h.stub(vim.ui, "select", function(_, _, on_choice) on_choice("Eliminar") end, function()
      press(sidebar, "d")
    end)
    assert.equals(0, vim.fn.filereadable(home .. "/.claude/projects/-p/abc-123.jsonl"))
    assert.is_nil(h.find_line(sidebar, " Claude "))
  end)

  it("renombrar una sesión conserva la limpieza al terminar el proceso", function()
    local dir = project_dir()
    vim.cmd("CopilotCli")
    local buf = state.Copilot.buf
    local sidebar = open_project_agents(dir)
    goto_line(sidebar, "Copilot")
    h.stub(vim.ui, "input", function(_, on_confirm) on_confirm("Revisor") end, function()
      press(sidebar, "i")
    end)
    assert.is_nil(state.Copilot)
    assert.equals(buf, state.Revisor.buf)

    vim.fn.jobstop(vim.b[buf].terminal_job_id)
    assert.is_true(h.wait_for(function() return state.Revisor == nil end))
  end)

  it("q dentro de un agente renombrado lo oculta en vez de crear otro", function()
    project_dir()
    vim.cmd("CopilotCli")
    local buf = state.Copilot.buf
    state.Revisor, state.Copilot = state.Copilot, nil
    h.stub(vim.fn, "input", function() error("no debe pedir carpeta") end, function()
      press(buf, "q")
    end)
    assert.equals(buf, state.Revisor.buf)
    assert.is_nil(state.Revisor.win)
  end)
end)

describe("AgentHub: panel de cambios Git", function()
  after_each(reset)

  it("muestra el árbol de archivos modificados y abre su diff", function()
    local dir = project_dir()
    h.write(dir .. "/src/app.lua", "print(2)")
    local _, changes = open_hub()
    goto_line(changes, "")
    press(changes, "<CR>")
    goto_line(changes, " src")
    press(changes, "<CR>")
    assert.is_not_nil(h.find_line(changes, "ARCHIVOS MODIFICADOS"))
    assert.is_not_nil(h.find_line(changes, "1 archivo(s) modificado(s)"))
    goto_line(changes, "app.lua")
    press(changes, "<CR>")
    local diff = vim.api.nvim_get_current_buf()
    assert.equals("diff", vim.bo[diff].filetype)
    assert.is_not_nil(h.find_line(diff, "+print(2)"))
    press(diff, "q")
    assert.equals(changes, vim.api.nvim_get_current_buf())
  end)

  it("Enter sobre una carpeta la pliega y despliega", function()
    local dir = project_dir()
    h.write(dir .. "/src/app.lua", "print(2)")
    local _, changes = open_hub()
    goto_line(changes, "")
    press(changes, "<CR>")
    goto_line(changes, " src")
    assert.is_nil(h.find_line(changes, "app.lua"))
    press(changes, "<CR>")
    assert.is_not_nil(h.find_line(changes, "app.lua"))
    goto_line(changes, " src")
    press(changes, "<CR>")
    assert.is_nil(h.find_line(changes, "app.lua"))
  end)

  it("el menú de repositorios agrega otro repo y vuelve al panel de cambios", function()
    project_dir()
    local other = h.git_repo()
    local _, changes = open_hub()
    press(changes, "g")
    local menu = vim.api.nvim_get_current_buf()
    assert.equals("agent-repositories", vim.bo[menu].filetype)
    h.stub(vim.fn, "input", function() return other end, function()
      press(menu, "a")
    end)
    local reopened = vim.api.nvim_get_current_buf()
    assert.equals("agent-repositories", vim.bo[reopened].filetype)
    assert.is_not_nil(h.find_line(reopened, vim.fn.fnamemodify(other, ":~")))
    press(reopened, "q")
    assert.equals(changes, vim.api.nvim_get_current_buf())
  end)

  it("g sobre un proyecto lo fija y rechaza carpetas inexistentes", function()
    local dir = project_dir()
    local sidebar = open_hub()
    goto_line(sidebar, vim.fn.fnamemodify(dir, ":t"))
    local messages = h.capture_notify(function() press(sidebar, "g") end)
    assert.matches("Proyecto fijado", messages[1].msg)
    assert.is_true(projects.list()[1].pinned)

    pcall(vim.cmd, "AgentHubClose")
    local data = vim.json.decode(table.concat(vim.fn.readfile(vim.fn.stdpath("state") .. "/projects.json"), ""))
    table.insert(data, { path = "/no/existe/proyecto", last = os.time() + 10 })
    vim.fn.writefile({ vim.json.encode(data) }, vim.fn.stdpath("state") .. "/projects.json")
    sidebar = open_hub()
    goto_line(sidebar, "proyecto")
    messages = h.capture_notify(function() press(sidebar, "g") end)
    assert.equals("La carpeta del proyecto no existe", messages[1].msg)
    for _, entry in ipairs(projects.list()) do
      assert.is_false(entry.path == "/no/existe/proyecto" and entry.pinned == true)
    end
  end)
end)

describe("AgentHub: espacio de trabajo", function()
  after_each(function()
    reset()
    vim.env.PATH = original_path
  end)

  it(":AgentWorkspace abre agente y cambios lado a lado", function()
    project_dir()
    vim.cmd("CopilotCli")
    vim.cmd("AgentWorkspace Copilot")
    local session = state.Copilot
    assert.equals(session.buf, vim.api.nvim_win_get_buf(session.win))
    assert.is_true(vim.api.nvim_win_is_valid(session.changes_win))
    local changes = vim.api.nvim_win_get_buf(session.changes_win)
    assert.equals("agent-changes", vim.bo[changes].filetype)
  end)

  it(":AgentWorkspace avisa si el agente no existe", function()
    local messages = h.capture_notify(function() vim.cmd("AgentWorkspace Nadie") end)
    assert.equals("Agente no encontrado: Nadie", messages[1].msg)
  end)
end)
