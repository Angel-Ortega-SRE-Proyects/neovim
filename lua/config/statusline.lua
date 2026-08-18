-- Barra de estado hecha a mano (sin plugin), una sola franja global abajo,
-- estilo VSCode: rama de git, diagnósticos, archivo, CPU/MEM/DISK, posición,
-- encoding. Se actualiza en tiempo real. Edita M.render() a tu gusto.
local M = {}

local sysmonitor = require("config.sysmonitor")
local git = require("config.git")
sysmonitor.start(3000)
git.start_watch()

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
  return string.format("  %s%s", head, dirty)
end

local function diagnostics()
  local ok, counts = pcall(vim.diagnostic.count)
  if not ok then
    return ""
  end
  local errors = counts[vim.diagnostic.severity.ERROR] or 0
  local warnings = counts[vim.diagnostic.severity.WARN] or 0
  return string.format(" %d  %d", errors, warnings)
end

local function filename()
  local name = vim.fn.expand("%:t")
  if name == "" then
    return "[No Name]"
  end
  local modified = vim.bo.modified and " ●" or ""
  return name .. modified
end

local function position()
  return string.format("Ln %d, Col %d", vim.fn.line("."), vim.fn.col("."))
end

local function fileinfo()
  local enc = vim.bo.fileencoding ~= "" and vim.bo.fileencoding or vim.o.encoding
  local fmt = vim.bo.fileformat:upper()
  local ft = vim.bo.filetype ~= "" and vim.bo.filetype or "text"
  return string.format("%s  %s  %s", enc:upper(), fmt, ft)
end

function M.render()
  local left = table.concat({
    git_branch(),
    diagnostics(),
    "  " .. filename(),
  }, "  ")

  local right = table.concat({
    sysmonitor.status(),
    position(),
    fileinfo(),
  }, "   ")

  return string.format(" %s%%=%s ", left, right)
end

function M.setup()
  vim.o.laststatus = 3
  vim.o.statusline = "%!v:lua.require('config.statusline').render()"

  -- CPU/MEM/DISK cambian solos (no por moverte); fuerza redibujar la barra
  -- cada pocos segundos para que se vea "en tiempo real".
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
