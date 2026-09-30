-- Abstracciones pequeñas para que la configuración funcione en Linux,
-- macOS y Windows sin repartir comprobaciones de plataforma por todo el
-- código.
local M = {}

local sysname = (vim.uv.os_uname().sysname or ""):lower()

M.name = sysname
M.is_windows = sysname:find("windows", 1, true) ~= nil
M.is_macos = sysname == "darwin"
M.is_linux = sysname == "linux"
M.path_separator = M.is_windows and "\\" or "/"

function M.join(...)
  local parts = { ... }
  local path = table.concat(parts, M.path_separator)
  if M.is_windows then
    return path:gsub("/", "\\")
  end
  return path:gsub("//+", "/")
end

function M.executable(command)
  return type(command) == "string" and vim.fn.executable(command) == 1
end

function M.open_external_command(path)
  if M.is_windows then
    return { "cmd.exe", "/c", "start", "", path }
  end
  if M.is_macos then
    return { "open", path }
  end
  return { "xdg-open", path }
end

-- /proc existe en Linux. En macOS usamos lsof si está disponible; en
-- Windows devolver nil es preferible a intentar leer una ruta Unix.
function M.process_cwd(pid)
  if type(pid) ~= "number" or pid <= 0 then
    return nil
  end
  if M.is_linux then
    return vim.uv.fs_readlink("/proc/" .. pid .. "/cwd")
  end
  if M.is_macos and M.executable("lsof") then
    local result = vim.system({ "lsof", "-a", "-p", tostring(pid), "-d", "cwd", "-Fn" }, { text = true }):wait()
    if result.code == 0 and type(result.stdout) == "string" then
      return result.stdout:match("\nn([^\n]+)")
    end
  end
  return nil
end

function M.monitor_command()
  if M.is_windows then
    return {
      "powershell.exe", "-NoProfile", "-Command",
      "Get-Process | Sort-Object CPU -Descending | Select-Object -First 20",
    }, "PowerShell"
  end
  if M.executable("btop") then return "btop", "btop" end
  if M.executable("htop") then return "htop", "htop" end
  return "top -o %CPU", "top"
end

return M
