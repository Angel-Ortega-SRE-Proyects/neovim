-- Franja superior dedicada al contexto del proyecto y recursos del sistema.
-- Los buffers y el archivo activo viven en la franja inferior.
local M = {}

local sysmonitor = require("config.sysmonitor")
local agent_usage = require("config.agent_usage")

local function literal(text)
  return (text or ""):gsub("%%", "%%%%")
end

local function project_label()
  local root = vim.g.project_root or vim.fn.getcwd()
  local path = vim.fn.fnamemodify(root, ":~")
  local name = vim.b.project_name or vim.fn.fnamemodify(root, ":t")
  local base = vim.fn.fnamemodify(root, ":t")
  return name ~= base and (path .. " · " .. name) or path
end

function M.render()
  local resources = literal(sysmonitor.status())
  local usage = literal(agent_usage.quota_summary())
  local right = resources
  if usage ~= "" then
    right = right .. "  ·  " .. usage
  end
  return " %#ToplineProject# " .. project_label() .. " %#ToplineResource#%=" .. right .. " %#StatusLine# "
end

function M.setup()
  vim.o.showtabline = 2
  vim.o.tabline = "%!v:lua.require('config.topline').render()"
  sysmonitor.start(3000)
  agent_usage.start(15000)
  local function set_highlights()
    local colors = require("config.theme").colors
    vim.api.nvim_set_hl(0, "ToplineProject", { fg = colors.tan, bold = true })
    vim.api.nvim_set_hl(0, "ToplineResource", { fg = colors.green_dim })
  end
  set_highlights()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("ToplineHighlights", { clear = true }),
    callback = set_highlights,
  })
  local timer = vim.uv.new_timer()
  timer:start(1000, 3000, vim.schedule_wrap(function()
    pcall(vim.cmd.redrawtabline)
  end))
end

return M
