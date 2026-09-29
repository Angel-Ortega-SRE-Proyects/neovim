local h = require("tests.spec_helpers")

describe("barra de estado", function()
  local statusline = require("config.statusline")
  local agents_status = require("config.agents_status")
  local copilot_status = require("config.copilot_status")

  after_each(function()
    agents_status.set(0, 0)
    copilot_status.set({})
    h.reset_ui()
    h.cleanup()
  end)

  it("muestra agentes visibles y ocultos solo cuando hay alguno", function()
    assert.is_nil(statusline.render():find("●%d"))
    agents_status.set(2, 1)
    local line = statusline.render()
    assert.matches("●2", line)
    assert.matches("○1", line)
  end)

  it("refleja cada estado de Copilot", function()
    local expected = { [""] = "○ Copilot", Normal = "● Copilot", InProgress = "◐ Copilot", Warning = "✕ Copilot" }
    for status, icon in pairs(expected) do
      copilot_status.set({ status = status, message = "m" })
      assert.is_truthy(statusline.render():find(icon, 1, true), status)
    end
    assert.equals("m", copilot_status.message)
  end)

  it("lista buffers con marca de modificado y el proyecto actual", function()
    local path = h.tempdir() .. "/archivo.lua"
    vim.cmd("edit " .. path)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "x" })
    vim.g.project_root = "/tmp/demo"
    local line = statusline.render()
    assert.is_truthy(line:find(vim.api.nvim_get_current_buf() .. ":archivo.lua ●", 1, true))
    assert.is_truthy(line:find("/tmp/demo", 1, true))
    assert.is_truthy(line:find("Ln 1, Col 1", 1, true))
    vim.bo.modified = false
  end)

  it("cuenta errores y warnings de diagnóstico", function()
    local ns = vim.api.nvim_create_namespace("ui-spec")
    vim.diagnostic.set(ns, 0, {
      { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = "e" },
      { lnum = 0, col = 0, severity = vim.diagnostic.severity.WARN, message = "w" },
      { lnum = 0, col = 0, severity = vim.diagnostic.severity.WARN, message = "w2" },
    })
    local line = statusline.render()
    assert.is_truthy(line:find("StatuslineError# 1", 1, true))
    assert.is_truthy(line:find("StatuslineWarn# 2", 1, true))
    vim.diagnostic.reset(ns)
  end)

  it("setup es idempotente: no acumula timers en cada recarga", function()
    statusline.setup()
    local timer = statusline.timer
    statusline.setup()
    assert.equals(timer, statusline.timer)
    assert.equals("%!v:lua.require'config.statusline'.render()", vim.o.statusline)
  end)
end)

describe("expresiones de las barras", function()
  it("Vim puede evaluar statusline y tabline (sin E5101) y sobreviven a un redraw", function()
    require("config.statusline").setup()
    require("config.topline").setup()
    for _, option in ipairs({ "statusline", "tabline" }) do
      local expression = vim.o[option]:gsub("^%%!", "")
      assert.is_string(vim.fn.eval(expression), option)
    end
    vim.cmd("redraw!")
    assert.matches("config.statusline", vim.o.statusline)
    assert.matches("config.topline", vim.o.tabline)
  end)
end)

describe("franja superior", function()
  local topline = require("config.topline")

  it("muestra proyecto, recursos y cuotas escapando %", function()
    vim.g.project_root = "/tmp/demo"
    local usage = require("config.agent_usage")
    usage.quotas.Codex = { session_remaining = 60 }
    local line = topline.render()
    assert.is_truthy(line:find("/tmp/demo", 1, true))
    assert.is_truthy(line:find("Codex 5h 40%%", 1, true))
    usage.quotas.Codex = nil
  end)

  it("setup es idempotente", function()
    topline.setup()
    local timer = topline.timer
    topline.setup()
    assert.equals(timer, topline.timer)
    assert.equals(2, vim.o.showtabline)
  end)
end)

describe("monitor del sistema", function()
  local sysmonitor = require("config.sysmonitor")

  it("formatea tasas en KB/s y MB/s", function()
    assert.equals("2KB/s", sysmonitor.fmt_rate(2048))
    assert.equals("3.0MB/s", sysmonitor.fmt_rate(3 * 1024 * 1024))
  end)

  it("start es idempotente y lee memoria real", function()
    local timer = sysmonitor.start(60000)
    assert.equals(timer, sysmonitor.start(60000))
    local values = sysmonitor.values()
    assert.is_true(values.mem_total_gb > 0)
    assert.is_true(values.mem_used_gb <= values.mem_total_gb)
    assert.matches("GB", sysmonitor.status())
  end)
end)

describe("temas", function()
  local theme = require("config.theme")
  local palette_file = vim.fn.stdpath("data") .. "/nvim-theme"

  after_each(h.reset_ui)

  it("cada tema tiene paleta completa y un colorscheme", function()
    local keys = vim.tbl_keys(theme.palettes.verde)
    for name, spec in pairs(theme.themes) do
      assert.is_table(theme.palettes[name], name)
      assert.matches("^tokyonight", spec.scheme)
      for _, key in ipairs(keys) do
        assert.is_string(theme.palettes[name][key], name .. "." .. key)
      end
    end
  end)

  it("registra :ThemeSelect y :ThemeReload", function()
    assert.equals(2, vim.fn.exists(":ThemeSelect"))
    assert.equals(2, vim.fn.exists(":ThemeReload"))
  end)

  it("el selector navega, aplica y persiste el tema elegido", function()
    theme.select()
    local buf = vim.api.nvim_get_current_buf()
    assert.equals(11, #h.lines(buf))
    local cursor = vim.api.nvim_win_get_cursor(0)[1]
    h.press("j")
    assert.equals(5, cursor) -- "verde" (2.º) es el tema por defecto
    assert.equals(6, vim.api.nvim_win_get_cursor(0)[1])
    h.press("3")
    assert.is_false(vim.api.nvim_buf_is_valid(buf))
    assert.equals("ambar", theme.active)
    assert.equals(theme.palettes.ambar.bg, theme.colors.bg)
    assert.equals("tokyonight-storm", vim.g.colors_name)
    assert.same({ "ambar" }, vim.fn.readfile(palette_file))
    local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
    assert.equals(tonumber(theme.palettes.ambar.bg:sub(2), 16), normal.bg)
  end)

  it("Esc cierra el selector sin cambiar el tema", function()
    local active = theme.active
    theme.select()
    local buf = vim.api.nvim_get_current_buf()
    h.press("<Esc>")
    assert.is_false(vim.api.nvim_buf_is_valid(buf))
    assert.equals(active, theme.active)
  end)
end)

describe("índice de comandos", function()
  local dashboard = require("config.dashboard")
  dashboard.setup()

  it(":Commands abre el índice agrupado y q lo cierra", function()
    vim.cmd("Commands")
    local buf = vim.api.nvim_get_current_buf()
    assert.equals("commandsdashboard", vim.bo[buf].filetype)
    assert.is_not_nil(h.find_line(buf, "ÍNDICE DE COMANDOS Y ATAJOS"))
    assert.is_not_nil(h.find_line(buf, "Git"))
    assert.is_not_nil(h.find_line(buf, ":Commands"))
    vim.cmd("bwipeout")
    assert.is_false(vim.api.nvim_buf_is_valid(buf))
  end)

  it(":? en la línea de comandos abre el índice", function()
    local map = vim.fn.maparg("<CR>", "c", false, true)
    assert.is_function(map.callback)
    assert.equals("<CR>", map.callback())
  end)
end)

describe("alertas", function()
  local alerts = require("config.alerts")

  it("usa popups de notify para mensajes y errores", function()
    local options = alerts.options()
    assert.equals("notify", options.messages.view)
    assert.equals("notify", options.messages.view_error)
    assert.equals(6000, options.views.notify.timeout)
  end)

  it("aplica los resaltados y tolera que noice no esté instalado", function()
    alerts.apply_highlights()
    assert.is_not_nil(vim.api.nvim_get_hl(0, { name = "NoiceNotify" }).bg)
    assert.has_no_error(alerts.setup)
  end)
end)

describe("uso y cuotas de agentes", function()
  local usage = require("config.agent_usage")
  local original_home = vim.env.HOME
  local original_cwd = vim.fn.getcwd()

  before_each(function()
    usage.data, usage.quotas, usage.quota_alerts = {}, {}, {}
    usage.active_quota_agent = nil
    usage.codex_quota_refreshed_at = os.time()
  end)

  after_each(function()
    vim.env.HOME = original_home
    vim.cmd("cd " .. original_cwd)
    h.reset_ui()
    h.cleanup()
  end)

  it("escapa literales SQL duplicando comillas", function()
    assert.equals("'/tmp/o''neil'", usage.sql_quote("/tmp/o'neil"))
  end)

  it("suma tokens de la sesión más reciente de Claude y Codex para el cwd", function()
    local home = h.tempdir()
    local cwd = h.tempdir()
    vim.env.HOME = home
    vim.cmd("cd " .. cwd)
    h.write(home .. "/.claude/projects/" .. cwd:gsub("/", "-") .. "/s.jsonl", h.jsonl({
      { type = "assistant", message = { usage = { input_tokens = 100, output_tokens = 50 } } },
      { type = "assistant", message = { usage = { cache_read_input_tokens = 850 } } },
    }))
    h.write(home .. "/.codex/sessions/2026/01/02/s.jsonl", h.jsonl({
      { type = "session_meta", payload = { cwd = cwd } },
      { type = "event_msg", payload = { type = "token_count", info = { total_token_usage = { total_tokens = 2000 } } } },
    }))
    usage.refresh()
    assert.equals(1000, usage.data["Claude Code"].tokens)
    assert.near(0.006, usage.data["Claude Code"].cost, 1e-9)
    assert.equals(2000, usage.data.Codex.tokens)
    assert.equals(3000, usage.total().tokens)
    assert.is_true(usage.total().is_estimate)
  end)

  it("lee las cuotas que Codex muestra en su terminal", function()
    vim.cmd("cd " .. h.tempdir())
    local buf = vim.api.nvim_create_buf(false, true)
    local chan = vim.api.nvim_open_term(buf, {})
    vim.api.nvim_chan_send(chan, "OpenAI Codex\r\n5h limit: 40% left (resets 14:00)\r\nWeekly limit: 70% left (resets 3 Oct)\r\n")
    h.wait_for(function() return h.find_line(buf, "Weekly limit") ~= nil end)
    usage.refresh_quotas()
    assert.same({ session_remaining = 40, session_reset = "14:00", weekly_remaining = 70, weekly_reset = "3 Oct" },
      usage.quotas.Codex)
    assert.equals("Codex 5h 60% → 14:00 · 7d 30% → 3 Oct", usage.quota_summary())
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("lee el snapshot de límites de Claude y avisa una sola vez por nivel", function()
    local cwd = h.tempdir()
    vim.cmd("cd " .. cwd)
    h.write(cwd .. "/.claude/usage_limits.json", vim.json.encode({
      five_hour = { used_percentage = 85 }, seven_day = { used_percentage = 10 },
    }))
    local messages = h.capture_notify(function()
      usage.activate_quota_monitor("Claude Code")
      usage.refresh_quotas()
    end)
    assert.equals(15, usage.quotas["Claude Code"].session_remaining)
    assert.equals(1, #messages)
    assert.equals(vim.log.levels.WARN, messages[1].level)
    assert.matches("85%% de la ventana de 5h", messages[1].msg)
  end)

  it("session_summary omite agentes con cuota y filtra por agente activo", function()
    usage.data = { ["Claude Code"] = { tokens = 1500 }, Gemini = { tokens = 2500000 }, Codex = { tokens = 10 } }
    usage.quotas.Codex = { session_remaining = 50 }
    assert.equals("Claude 1.5K tok  |  Gemini 2.5M tok", usage.session_summary())
    usage.active_quota_agent = "Gemini"
    assert.equals("Gemini 2.5M tok", usage.session_summary())
  end)
end)
