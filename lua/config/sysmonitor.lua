-- Uso de CPU / memoria / disco / red, leído de /proc y refrescado en segundo
-- plano. Se usa como componente de lualine (barra inferior). Personalizable:
-- cambia el intervalo o el formato de M.status() a tu gusto.
-- CPU se muestra en %; memoria y disco en GB usados/total; red en KB/s o MB/s.
local M = {}

local cpu_pct = 0
local mem_used_gb, mem_total_gb = 0, 0
local disk_used_gb, disk_total_gb = 0, 0
local net_rx_rate, net_tx_rate = 0, 0 -- bytes/seg

local prev_idle, prev_total = 0, 0
local prev_rx, prev_tx = nil, nil
local prev_net_time = nil

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
    -- /proc/meminfo reporta en KiB
    mem_total_gb = total / 1024 / 1024
    mem_used_gb = (total - avail) / 1024 / 1024
  end
end

local function read_disk()
  vim.system({ "df", "--output=used,size", "--block-size=1K", "/" }, { text = true }, function(res)
    if res.code ~= 0 or not res.stdout then
      return
    end
    local used, size = res.stdout:match("(%d+)%s+(%d+)%s*\n?%s*$")
    if used and size then
      disk_used_gb = tonumber(used) / 1024 / 1024
      disk_total_gb = tonumber(size) / 1024 / 1024
    end
  end)
end

local function read_net()
  local f = io.open("/proc/net/dev", "r")
  if not f then
    return
  end
  local rx, tx = 0, 0
  for line in f:lines() do
    local iface, rest = line:match("^%s*([%w%-@%.]+):%s*(.*)$")
    if iface and iface ~= "lo" then
      local fields = {}
      for n in rest:gmatch("%d+") do
        table.insert(fields, tonumber(n))
      end
      rx = rx + (fields[1] or 0) -- bytes recibidos
      tx = tx + (fields[9] or 0) -- bytes transmitidos
    end
  end
  f:close()

  local now = vim.uv.hrtime() / 1e9
  if prev_rx and prev_tx and prev_net_time then
    local dt = now - prev_net_time
    if dt > 0 then
      net_rx_rate = math.max(0, (rx - prev_rx) / dt)
      net_tx_rate = math.max(0, (tx - prev_tx) / dt)
    end
  end
  prev_rx, prev_tx, prev_net_time = rx, tx, now
end

local function tick()
  read_cpu()
  read_mem()
  read_disk()
  read_net()
end

function M.start(interval_ms)
  tick()
  local timer = vim.uv.new_timer()
  timer:start(1000, interval_ms or 3000, vim.schedule_wrap(tick))
  return timer
end

--- Formatea una tasa en bytes/seg como KB/s o MB/s.
function M.fmt_rate(bytes_per_sec)
  local kb = bytes_per_sec / 1024
  if kb >= 1024 then
    return string.format("%.1fMB/s", kb / 1024)
  end
  return string.format("%.0fKB/s", kb)
end

--- Texto corto para la barra de estado, ej:
--- " 12%  47%  47.0/62.7GB  63%  120.5/450.0GB  1.2/0.3MB/s"
function M.status()
  return string.format(
    " %d%%  󰍛 %.1f/%.1fGB  󰋊 %.0f/%.0fGB  󰛳 ↓%s ↑%s",
    cpu_pct,
    mem_used_gb,
    mem_total_gb,
    disk_used_gb,
    disk_total_gb,
    M.fmt_rate(net_rx_rate),
    M.fmt_rate(net_tx_rate)
  )
end

function M.values()
  return {
    cpu = cpu_pct,
    mem_used_gb = mem_used_gb,
    mem_total_gb = mem_total_gb,
    disk_used_gb = disk_used_gb,
    disk_total_gb = disk_total_gb,
    net_rx_bytes_per_sec = net_rx_rate,
    net_tx_bytes_per_sec = net_tx_rate,
  }
end

return M
