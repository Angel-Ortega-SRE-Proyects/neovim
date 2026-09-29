local h = require("tests.spec_helpers")
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

describe("specs de plugins (lazy.nvim)", function()
  it("cada archivo de lua/plugins carga y devuelve una tabla", function()
    for _, path in ipairs(vim.fn.glob(root .. "/lua/plugins/*.lua", false, true)) do
      local name = "plugins." .. vim.fn.fnamemodify(path, ":t:r")
      local ok, spec = pcall(require, name)
      assert.is_true(ok, name .. ": " .. tostring(spec))
      assert.is_table(spec, name)
    end
  end)

  it("los specs con plugin declaran un repositorio usuario/repo", function()
    local function check(spec, name)
      if type(spec[1]) == "string" then
        assert.matches("^[%w%-_.]+/[%w%-_.]+$", spec[1], name)
      else
        for _, child in ipairs(spec) do
          if type(child) == "table" then check(child, name) end
        end
      end
    end
    for _, path in ipairs(vim.fn.glob(root .. "/lua/plugins/*.lua", false, true)) do
      local name = "plugins." .. vim.fn.fnamemodify(path, ":t:r")
      check(require(name), name)
    end
  end)

  it("Copilot habilita gitcommit y deja <Tab> a nvim-cmp", function()
    local spec = require("plugins.copilot")
    assert.equals("zbirenbaum/copilot.lua", spec[1])
    assert.is_true(spec.opts.filetypes.gitcommit)
    assert.is_false(spec.opts.suggestion.keymap.accept)
    assert.equals("<C-]>", spec.opts.suggestion.keymap.dismiss)
  end)
end)

describe("terminales", function()
  require("plugins.terminal")

  after_each(function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" then
        pcall(vim.fn.jobstop, vim.b[buf].terminal_job_id)
      end
    end
    h.reset_ui()
  end)

  it(":Term abre una pestaña de terminal, ejecuta el comando y la reutiliza", function()
    local tabs = #vim.api.nvim_list_tabpages()
    vim.cmd("Term echo hola-term")
    local buf = vim.api.nvim_get_current_buf()
    assert.equals("terminal", vim.bo[buf].buftype)
    assert.is_true(#vim.api.nvim_list_tabpages() > tabs)
    local after_first = #vim.api.nvim_list_tabpages()
    assert.is_true(h.wait_for(function() return h.find_line(buf, "hola-term") ~= nil end, 5000))
    vim.cmd("stopinsert")
    vim.cmd("tabfirst")
    vim.cmd("Term")
    assert.equals(buf, vim.api.nvim_get_current_buf())
    assert.equals(after_first, #vim.api.nvim_list_tabpages())
  end)

  it(":Tb avisa fuera de tmux", function()
    local tmux = vim.env.TMUX
    vim.env.TMUX = nil
    local messages = h.capture_notify(function() vim.cmd("Tb") end)
    vim.env.TMUX = tmux
    assert.matches("tmux", messages[1].msg)
  end)

  it(":Sys abre el monitor en flotante con q para cerrar", function()
    local command
    h.stub(vim.fn, "termopen", function(cmd) command = cmd return 1 end, function()
      vim.cmd("Sys")
    end)
    assert.matches("top", command)
    local win = vim.api.nvim_get_current_win()
    assert.equals("editor", vim.api.nvim_win_get_config(win).relative)
    assert.is_not_nil(vim.fn.maparg("q", "n", false, true).rhs)
  end)

  it("registra atajos de terminal", function()
    assert.equals("<Cmd>Term<CR>", vim.fn.maparg(" tt", "n", false, true).rhs:gsub("<cmd>", "<Cmd>"))
    assert.equals("<Cmd>Sys<CR>", vim.fn.maparg(" ts", "n", false, true).rhs:gsub("<cmd>", "<Cmd>"))
  end)
end)

describe("comandos htx", function()
  require("plugins.htx")

  after_each(h.reset_ui)

  local function run(command)
    local argv
    h.stub(vim.fn, "termopen", function(cmd) argv = cmd return 1 end, function()
      vim.cmd(command)
    end)
    return argv
  end

  it("usan el perfil y reglas por defecto", function()
    assert.same({ "htx", "init", "software_developer", "--assistant", "claude" }, run("HtxInit"))
    h.reset_ui()
    assert.same({ "htx", "profile", "load", "software_developer", "--assistant", "claude" }, run("HtxProfile"))
    h.reset_ui()
    assert.same({ "htx", "task", "load-rules", "--rules", "all" }, run("HtxRules"))
  end)

  it("pasan el argumento como un solo parámetro, sin interpretarlo en un shell", function()
    assert.same({ "htx", "task", "load-rules", "--rules", "a,b;touch /tmp/x" }, run("HtxRules a,b;touch /tmp/x"))
  end)
end)

describe("recarga en caliente del Agent Hub", function()
  it("vuelve a registrar los comandos y reabre el hub si estaba abierto", function()
    require("plugins.ai_cli")
    vim.cmd("Agents")
    require("config.agent_hub_reload").apply()
    assert.equals(2, vim.fn.exists(":Grok"))
    assert.equals(2, vim.fn.exists(":Agents"))
    local hubs = 0
    for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
      local ok, is_hub = pcall(vim.api.nvim_tabpage_get_var, tabpage, "agent_hub")
      if ok and is_hub then hubs = hubs + 1 end
    end
    assert.equals(1, hubs)
    vim.cmd("AgentHubClose")
  end)
end)

describe("logo animado", function()
  it("render produce un frame del tamaño pedido con solo 0/1/espacios", function()
    local logo = require("config.dashboard_logo")
    local lines = logo.render(logo.WIDTH, logo.HEIGHT, 0)
    assert.equals(logo.HEIGHT, #lines)
    for _, line in ipairs(lines) do
      assert.equals(logo.WIDTH, #line)
      assert.is_nil(line:find("[^01 ]"))
    end
    assert.are_not.same(lines, logo.render(logo.WIDTH, logo.HEIGHT, logo.SPEED * 10))
  end)
end)
