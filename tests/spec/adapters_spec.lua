local adapters = require("config.agent_adapters")
local integrations = require("config.integrations")
local platform = require("config.platform")

describe("adaptadores de agentes", function()
  it("registra los seis proveedores sin acoplar el Hub a sus CLIs", function()
    local all = adapters.all()
    assert.equals(6, #all)
    assert.equals("config.agent_sessions.claude", adapters.get("claude").module)
    assert.same({ "AGENTS.md" }, adapters.get("codex").rules)
  end)

  it("resuelve el archivo de reglas existente por prioridad", function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.github", "p")
    vim.fn.writefile({ "reglas" }, root .. "/AGENTS.md")
    assert.equals(root .. "/AGENTS.md", adapters.rule_file("copilot", root))
    vim.fn.delete(root, "rf")
  end)

  it("permite desactivar un adaptador sin eliminar su definición", function()
    local previous = vim.g.nvim_agent_adapters
    vim.g.nvim_agent_adapters = { gemini = { enabled = false } }
    assert.is_false(adapters.get("gemini").enabled)
    for _, adapter in ipairs(adapters.enabled()) do
      assert.not_equals("gemini", adapter.id)
    end
    vim.g.nvim_agent_adapters = previous
  end)

  it("usa los flags globales de integraciones", function()
    local previous = vim.g.nvim_enable_htx
    vim.g.nvim_enable_htx = false
    assert.is_false(integrations.enabled("htx"))
    vim.g.nvim_enable_htx = previous
    assert.is_true(integrations.enabled("htx"))
  end)

  it("expone comandos externos apropiados para la plataforma", function()
    local command = platform.open_external_command("archivo.txt")
    assert.is_table(command)
    if platform.is_windows then
      assert.equals("cmd.exe", command[1])
    elseif platform.is_macos then
      assert.equals("open", command[1])
    else
      assert.equals("xdg-open", command[1])
    end
  end)
end)
