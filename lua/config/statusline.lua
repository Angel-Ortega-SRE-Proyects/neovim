-- Barra inferior única: buffers abiertos, proyecto, Git, diagnósticos,
-- agentes, sistema, archivo activo, posición y encoding.
local M = {}

local git = require("config.git")
local agents_status = require("config.agents_status")
local copilot_status = require("config.copilot_status")
git.start_watch()

-- Agentes de IA corriendo (lua/plugins/ai_cli.lua): ●N visibles, ○N
-- ocultos en segundo plano. Vacío si no hay ninguno.
local function agents()
  local visible, hidden = agents_status.visible, agents_status.hidden
  if visible == 0 and hidden == 0 then
    return ""
  end
  local parts = {}
  if visible > 0 then
    table.insert(parts, string.format("●%d", visible))
  end
  if hidden > 0 then
    table.insert(parts, string.format("○%d", hidden))
  end
  return string.format("%%#StatuslineAgents#%s%%#StatusLine#", table.concat(parts, " "))
end

-- Estado de GitHub Copilot (lua/plugins/copilot.lua, vía
-- config/copilot_status.lua): ● listo, ◐ pensando, ✕ warning/error, ○
-- apagado/sin arrancar todavía.
local function copilot()
  local status = copilot_status.status
  local icon, hl
  if status == "InProgress" then
    icon, hl = "◐ Copilot", "StatuslineCopilotBusy"
  elseif status == "Warning" then
    icon, hl = "✕ Copilot", "StatuslineCopilotWarn"
  elseif status == "Normal" then
    icon, hl = "● Copilot", "StatuslineCopilotOk"
  else
    icon, hl = "○ Copilot", "StatuslineCopilotOff"
  end
  return string.format("%%#%s#%s%%#StatusLine#", hl, icon)
end

local function git_branch()
  local head = git.branch()
  if head == "" then
    return ""
  end
  local dirty = ""
  local status = vim.b.gitsigns_status_dict
  if status and ((status.added or 0) + (status.changed or 0) + (status.removed or 0)) > 0 then
    dirty = "*"
  end
  return string.format("%%#StatuslineGitBranch#\u{f126} %s%s%%#StatusLine#", head, dirty)
end

local function diagnostics()
  local ok, counts = pcall(vim.diagnostic.count)
  if not ok then
    return ""
  end
  local errors = counts[vim.diagnostic.severity.ERROR] or 0
  local warnings = counts[vim.diagnostic.severity.WARN] or 0
  local parts = {}
  if errors > 0 then
    table.insert(parts, string.format("%%#StatuslineError# %d%%#StatusLine#", errors))
  end
  if warnings > 0 then
    table.insert(parts, string.format("%%#StatuslineWarn# %d%%#StatusLine#", warnings))
  end
  return table.concat(parts, " ")
end

local function filename()
  local name = vim.fn.expand("%:t")
  if name == "" then
    return "[No Name]"
  end
  local modified = vim.bo.modified and " %#StatuslineWarn#●%#StatusLine#" or ""
  return name .. modified
end

local function buffers()
  local current = vim.api.nvim_get_current_buf()
  local items = {}
  local infos = vim.fn.getbufinfo({ buflisted = 1 })
  table.sort(infos, function(a, b) return a.bufnr < b.bufnr end)
  for _, info in ipairs(infos) do
    local buftype = vim.bo[info.bufnr].buftype
    local filetype = vim.bo[info.bufnr].filetype
    if buftype == "" and filetype ~= "NvimTree" then
      local name = info.name ~= "" and vim.fn.fnamemodify(info.name, ":t") or "[No Name]"
      if #name > 18 then
        name = name:sub(1, 17) .. "…"
      end
      local marker = info.changed == 1 and " ●" or ""
      local hl = info.bufnr == current and "StatuslineBufferActive" or "StatuslineBuffer"
      table.insert(items, string.format("%%#%s# %d:%s%s %%#StatusLine#", hl, info.bufnr, name, marker))
    end
  end
  return table.concat(items)
end

local function project()
  local root = vim.g.project_root or vim.fn.getcwd()
  if not root or root == "" then
    return ""
  end
  local path = vim.fn.fnamemodify(root, ":~")
  local name = vim.b.project_name or vim.fn.fnamemodify(root, ":t")
  local basename = vim.fn.fnamemodify(root, ":t")
  local suffix = name ~= basename and (" · " .. name) or ""
  local active = vim.fn.expand("%:t")
  if active ~= "" and active ~= name then
    suffix = suffix .. " · " .. active
  end
  return "%#StatuslineProject# " .. path .. suffix .. " %#StatusLine#"
end

local function position()
  return string.format("%%#StatuslinePos#Ln %d, Col %d%%#StatusLine#", vim.fn.line("."), vim.fn.col("."))
end

local function fileinfo()
  local enc = vim.bo.fileencoding ~= "" and vim.bo.fileencoding or vim.o.encoding
  local fmt = vim.bo.fileformat:upper()
  local ft = vim.bo.filetype ~= "" and vim.bo.filetype or "text"
  return string.format("%%#StatuslineDim#%s  %s  %s%%#StatusLine#", enc:upper(), fmt, ft)
end

local function theme_name()
  local name = require("config.theme").active or "verde"
  return "%#StatuslineTheme#" .. name .. "%#StatusLine#"
end

function M.render()
  local left = table.concat({
    buffers(),
    project(),
    git_branch(),
    agents(),
    copilot(),
    diagnostics(),
  }, "  ")

  local right = table.concat({
    theme_name(),
    position(),
    fileinfo(),
  }, "   ")

  return string.format(" %s%%=%s ", left, right)
end

-- Un color por sección para distinguir cada dato de un vistazo. Paleta
-- centralizada en lua/config/theme.lua (la misma que usan dashboard.lua y
-- explorer.lua). Se reaplica en cada ColorScheme porque cambiar de tema
-- borra los highlights custom.
local colors = require("config.theme").colors
local function set_highlights()
  vim.api.nvim_set_hl(0, "StatuslineGitBranch", { fg = colors.brown, bold = true })
  vim.api.nvim_set_hl(0, "StatuslineAgents", { fg = colors.green, bold = true })
  vim.api.nvim_set_hl(0, "StatuslineError", { fg = colors.error, bold = true })
  vim.api.nvim_set_hl(0, "StatuslineWarn", { fg = colors.warn, bold = true })
  vim.api.nvim_set_hl(0, "StatuslinePos", { fg = colors.fg })
  vim.api.nvim_set_hl(0, "StatuslineDim", { fg = colors.green_dim })
  vim.api.nvim_set_hl(0, "StatuslineBuffer", { fg = colors.green_dim })
  vim.api.nvim_set_hl(0, "StatuslineBufferActive", { fg = colors.green_bright, bold = true })
  vim.api.nvim_set_hl(0, "StatuslineProject", { fg = colors.tan, bold = true })
  vim.api.nvim_set_hl(0, "StatuslineTheme", { fg = colors.green, bold = true })
  vim.api.nvim_set_hl(0, "StatuslineCopilotOk", { fg = colors.green })
  vim.api.nvim_set_hl(0, "StatuslineCopilotBusy", { fg = colors.tan })
  vim.api.nvim_set_hl(0, "StatuslineCopilotWarn", { fg = colors.error, bold = true })
  vim.api.nvim_set_hl(0, "StatuslineCopilotOff", { fg = colors.green_dim })
end

function M.setup()
  vim.o.laststatus = 3
  vim.o.showtabline = 0
  vim.o.statusline = "%!v:lua.require('config.statusline').render()"

  set_highlights()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("StatuslineHighlights", { clear = true }),
    callback = set_highlights,
  })

  -- Los agentes de IA (lua/plugins/ai_cli.lua) cambian de estado solos, no
  -- por moverte en el buffer; fuerza redibujar la barra cada pocos segundos
  -- para que el indicador ●/○ se vea "en tiempo real".
  local timer = vim.uv.new_timer()
  timer:start(
    2000,
    2000,
    vim.schedule_wrap(function()
      pcall(vim.cmd.redrawstatus)
    end)
  )
end

return M
