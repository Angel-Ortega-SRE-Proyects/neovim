-- Barra de estado hecha a mano (sin plugin), una sola franja global abajo,
-- estilo VSCode: rama de git, diagnósticos, agentes de IA, archivo,
-- posición, encoding. CPU/MEM/DISK/NET y el resumen de cambios de la rama
-- viven en la barra de ARRIBA (lua/plugins/editor.lua, custom_areas de
-- bufferline). Se actualiza en tiempo real. Edita M.render() a tu gusto.
local M = {}

local git = require("config.git")
local agents_status = require("config.agents_status")
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

local function position()
  return string.format("%%#StatuslinePos#Ln %d, Col %d%%#StatusLine#", vim.fn.line("."), vim.fn.col("."))
end

local function fileinfo()
  local enc = vim.bo.fileencoding ~= "" and vim.bo.fileencoding or vim.o.encoding
  local fmt = vim.bo.fileformat:upper()
  local ft = vim.bo.filetype ~= "" and vim.bo.filetype or "text"
  return string.format("%%#StatuslineDim#%s  %s  %s%%#StatusLine#", enc:upper(), fmt, ft)
end

function M.render()
  local left = table.concat({
    git_branch(),
    agents(),
    diagnostics(),
    "  " .. filename(),
  }, "  ")

  local right = table.concat({
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
end

function M.setup()
  vim.o.laststatus = 3
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
