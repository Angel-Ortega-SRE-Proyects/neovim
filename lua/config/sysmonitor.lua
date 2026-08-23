-- Uso de CPU / memoria / disco / red, refrescado en segundo plano. Se usa
-- como componente de lualine (barra inferior). Personalizable: cambia el
-- intervalo o el formato de M.status() a tu gusto.
-- CPU se muestra en %; memoria y disco en GB usados/total; red en KB/s o MB/s.
--
-- Linux lee /proc (rápido, sin spawnear procesos); macOS no tiene /proc,
-- así que ahí se apoya en top/vm_stat/sysctl/netstat vía vim.system (async,
-- igual que ya hacía read_disk con `df`) — un poco más caro pero corre en
-- un timer de fondo, no bloquea la UI.
local M = {}

local is_mac = vim.uv.os_uname().sysname == "Darwin"

local cpu_pct = 0
local mem_used_gb, mem_total_gb = 0, 0
local disk_used_gb, disk_total_gb = 0, 0
local net_rx_rate, net_tx_rate = 0, 0 -- bytes/seg

local prev_idle, prev_total = 0, 0
local prev_rx, prev_tx = nil, nil
local prev_net_time = nil

local function read_cpu_linux()
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

-- `top -l 1 -n 0` imprime una línea "CPU usage: X% user, Y% sys, Z% idle"
-- y sale; no hay /proc en macOS para leerlo directo de un archivo.
local function read_cpu_mac()
  vim.system({ "top", "-l", "1", "-n", "0" }, { text = true }, function(res)
    if res.code ~= 0 or not res.stdout then
      return
    end
    local idle = res.stdout:match("(%d+%.?%d*)%%%s*idle")
    if idle then
      cpu_pct = math.floor((100 - tonumber(idle)) + 0.5)
    end
  end)
end

local function read_mem_linux()
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

-- Sin /proc/meminfo: memoria total vía sysctl, páginas libres/inactivas
-- vía vm_stat (en páginas de 4KiB) para aproximar lo "usado".
local function read_mem_mac()
  vim.system({ "sh", "-c", "sysctl -n hw.memsize; vm_stat" }, { text = true }, function(res)
    if res.code ~= 0 or not res.stdout then
      return
    end
    local total_bytes = tonumber(res.stdout:match("^(%d+)"))
    local page_size = tonumber(res.stdout:match("page size of (%d+) bytes")) or 4096
    local free_pages = tonumber(res.stdout:match("Pages free:%s*(%d+)")) or 0
    local inactive_pages = tonumber(res.stdout:match("Pages inactive:%s*(%d+)")) or 0
    if total_bytes and total_bytes > 0 then
      local avail_bytes = (free_pages + inactive_pages) * page_size
      mem_total_gb = total_bytes / 1024 / 1024 / 1024
      mem_used_gb = (total_bytes - avail_bytes) / 1024 / 1024 / 1024
    end
  end)
end

-- `df -k /` (bloques de 1K) es el único flag común entre GNU df (Linux) y
-- BSD df (macOS) — a diferencia de `--output=`/`--block-size=`, que son
-- solo de GNU.
local function read_disk()
  vim.system({ "df", "-k", "/" }, { text = true }, function(res)
    if res.code ~= 0 or not res.stdout then
      return
    end
    local data_line = res.stdout:match("\n(.-)\n?$")
    if not data_line then
      return
    end
    -- Columnas por posición, NO por "sacar los números de la línea": el
    -- nombre del dispositivo (/dev/sda3, /dev/nvme0n1p2) suele traer
    -- dígitos propios que arruinarían un gmatch("%d+") genérico.
    local cols = {}
    for tok in data_line:gmatch("%S+") do
      table.insert(cols, tok)
    end
    -- Filesystem 1K-blocks Used Available Use% Mounted-on (GNU y BSD)
    local size, used = tonumber(cols[2]), tonumber(cols[3])
    if used and size then
      disk_used_gb = used / 1024 / 1024
      disk_total_gb = size / 1024 / 1024
    end
  end)
end

local function apply_net_rate(rx, tx)
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

local function read_net_linux()
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
  apply_net_rate(rx, tx)
end

-- `netstat -ib` repite cada interfaz por familia de dirección (Link/inet/
-- inet6); se cuenta solo la primera fila de cada una para no duplicar.
local function read_net_mac()
  vim.system({ "netstat", "-ib" }, { text = true }, function(res)
    if res.code ~= 0 or not res.stdout then
      return
    end
    local rx, tx = 0, 0
    local seen = {}
    for line in res.stdout:gmatch("[^\n]+") do
      local iface = line:match("^(%S+)")
      if iface and iface ~= "lo0" and not seen[iface] then
        local cols = {}
        for col in line:gmatch("%S+") do
          table.insert(cols, col)
        end
        -- Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll
        local ibytes, obytes = tonumber(cols[7]), tonumber(cols[10])
        if ibytes and obytes then
          seen[iface] = true
          rx = rx + ibytes
          tx = tx + obytes
        end
      end
    end
    apply_net_rate(rx, tx)
  end)
end

local read_cpu = is_mac and read_cpu_mac or read_cpu_linux
local read_mem = is_mac and read_mem_mac or read_mem_linux
local read_net = is_mac and read_net_mac or read_net_linux

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
