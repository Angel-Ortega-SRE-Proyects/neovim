-- Uso de CPU / memoria / disco, leído de /proc y refrescado en segundo plano.
-- Se usa como componente de lualine (barra inferior). Personalizable: cambia
-- el intervalo o el formato de M.status() a tu gusto.
local M = {}

local cpu_pct, mem_pct, disk_pct = 0, 0, 0
local prev_idle, prev_total = 0, 0

local function read_cpu()
  local f = io.open("/proc/stat", "r")
  if not f then
    return
  end
  local line = f:read("*l")
  f:close()
  if not line then
    return
  end

  local nums = {}
  for n in line:gmatch("%d+") do
    table.insert(nums, tonumber(n))
  end

  local idle = (nums[4] or 0) + (nums[5] or 0)
  local total = 0
  for _, v in ipairs(nums) do
    total = total + v
  end

  local diff_idle = idle - prev_idle
  local diff_total = total - prev_total
  if diff_total > 0 then
    cpu_pct = math.floor((1 - diff_idle / diff_total) * 100 + 0.5)
  end
  prev_idle, prev_total = idle, total
end

local function read_mem()
  local f = io.open("/proc/meminfo", "r")
  if not f then
    return
  end
  local total, avail
  for line in f:lines() do
    local key, value = line:match("^(%a+):%s+(%d+)")
    if key == "MemTotal" then
      total = tonumber(value)
    elseif key == "MemAvailable" then
      avail = tonumber(value)
    end
    if total and avail then
      break
    end
  end
  f:close()
  if total and avail and total > 0 then
    mem_pct = math.floor((1 - avail / total) * 100 + 0.5)
  end
end

local function read_disk()
  vim.system({ "df", "--output=pcent", "/" }, { text = true }, function(res)
    if res.code ~= 0 or not res.stdout then
      return
    end
    local pct = res.stdout:match("(%d+)%%")
    if pct then
      disk_pct = tonumber(pct)
    end
  end)
end

local function tick()
  read_cpu()
  read_mem()
  read_disk()
end

function M.start(interval_ms)
  tick()
  local timer = vim.uv.new_timer()
  timer:start(1000, interval_ms or 3000, vim.schedule_wrap(tick))
  return timer
end

--- Texto corto para la barra de estado, ej: " 12%  47%  63%"
function M.status()
  return string.format("󰍛 %d%%  %d%%  %d%%", cpu_pct, mem_pct, disk_pct)
end

function M.values()
  return { cpu = cpu_pct, mem = mem_pct, disk = disk_pct }
end

return M
