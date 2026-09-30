-- Registro declarativo de agentes. Los parsers de sesiones siguen viviendo
-- en config/agent_sessions, pero el nombre, CLI, comando, reglas y módulo de
-- cada proveedor se cambian aquí, en un solo lugar.
local platform = require("config.platform")

local M = {}

local DEFAULTS = {
  {
    id = "claude", enabled = true, name = "Claude Code", kind = "Claude Code", cli = "claude",
    command = "Claude", module = "config.agent_sessions.claude",
    rules = { "CLAUDE.md", "AGENTS.md" },
  },
  {
    id = "codex", enabled = true, name = "Codex", kind = "Codex", cli = "codex",
    command = "Codex", module = "config.codex_sessions",
    rules = { "AGENTS.md" },
  },
  {
    id = "opencode", enabled = true, name = "OpenCode", kind = "OpenCode", cli = "opencode",
    command = "OpenCode", module = "config.agent_sessions.opencode",
    rules = { "AGENTS.md", "opencode.md" },
  },
  {
    id = "gemini", enabled = true, name = "Gemini", kind = "Gemini", cli = "gemini",
    command = "Gemini", module = "config.agent_sessions.gemini",
    rules = { "GEMINI.md", "AGENTS.md" },
  },
  {
    id = "copilot", enabled = true, name = "Copilot", kind = "Copilot", cli = "copilot",
    command = "CopilotCli", module = "config.agent_sessions.copilot",
    rules = { ".github/copilot-instructions.md", "AGENTS.md" },
  },
  {
    id = "grok", enabled = true, name = "Grok", kind = "Grok", cli = "grok",
    command = "Grok", module = "config.agent_sessions.grok",
    rules = { "AGENTS.md" },
  },
}

local function configured()
  local overrides = vim.g.nvim_agent_adapters
  if type(overrides) ~= "table" then
    return DEFAULTS
  end
  return vim.tbl_map(function(adapter)
    local override = overrides[adapter.id]
    if type(override) ~= "table" then return vim.deepcopy(adapter) end
    return vim.tbl_deep_extend("force", vim.deepcopy(adapter), override)
  end, DEFAULTS)
end

function M.all()
  return configured()
end

function M.enabled()
  return vim.tbl_filter(function(adapter)
    return adapter.enabled ~= false
  end, configured())
end

function M.get(id)
  local needle = tostring(id or ""):lower()
  for _, adapter in ipairs(configured()) do
    if adapter.id:lower() == needle or adapter.name:lower() == needle
        or adapter.command:lower() == needle then
      return adapter
    end
  end
  return nil
end

function M.available()
  return vim.tbl_filter(function(adapter)
    return platform.executable(adapter.cli)
  end, M.enabled())
end

function M.names(only_available)
  local source = only_available and M.available() or M.enabled()
  return vim.tbl_map(function(adapter) return adapter.name end, source)
end

function M.default_id()
  return vim.g.nvim_agent_default or vim.env.NVIM_AGENT_DEFAULT or "claude"
end

function M.rules_for(id, root)
  local adapter = M.get(id) or M.get(M.default_id())
  if not adapter then return {} end
  root = root or vim.fn.getcwd()
  return vim.tbl_map(function(relative)
    return platform.join(root, relative)
  end, adapter.rules or {})
end

function M.rule_file(id, root)
  for _, path in ipairs(M.rules_for(id, root)) do
    if vim.fn.filereadable(path) == 1 then return path end
  end
  return nil
end

return M
