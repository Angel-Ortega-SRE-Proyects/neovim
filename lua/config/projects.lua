-- Lista de carpetas recientes (como el "Open Recent" de VSCode), guardada
-- en disco para que sobreviva entre sesiones de Neovim. Se graba sola cada
-- vez que cambiás de cwd (VimEnter / :cd) -- lua/plugins/projects.lua tiene
-- el picker de Telescope que la usa.
local M = {}

local FILE = vim.fn.stdpath("state") .. "/projects.json"
local MAX_ENTRIES = 20

local function normalize(path)
  -- fnamemodify ":p" resuelve a absoluto; sacar la barra final para que
  -- "/a/b" y "/a/b/" no cuenten como dos carpetas distintas.
  local abs = vim.fn.fnamemodify(path, ":p")
  return abs:gsub("/$", "")
end

local function read_all()
  local f = io.open(FILE, "r")
  if not f then
    return {}
  end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then
    return {}
  end
  return data
end

local function write_all(list)
  local f = io.open(FILE, "w")
  if not f then
    return
  end
  f:write(vim.json.encode(list))
  f:close()
end

--- Lista de { path, last } ordenada por más reciente primero.
function M.list()
  local data = read_all()
  table.sort(data, function(a, b)
    return a.last > b.last
  end)
  return data
end

--- Registra (o actualiza el timestamp de) una carpeta. Solo carpetas
--- reales -- si el path ya no existe, no se guarda.
function M.record(path)
  local abs = normalize(path)
  if vim.fn.isdirectory(abs) ~= 1 then
    return
  end

  local data = read_all()
  local found = false
  for _, entry in ipairs(data) do
    if entry.path == abs then
      entry.last = os.time()
      found = true
      break
    end
  end
  if not found then
    table.insert(data, { path = abs, last = os.time() })
  end

  table.sort(data, function(a, b)
    return a.last > b.last
  end)
  while #data > MAX_ENTRIES do
    table.remove(data)
  end

  write_all(data)
end

--- Alias custom para mostrar en el picker en vez de la ruta (ej. "API
--- backend" en vez de "~/work/proyectos/backend-service-v2"). name = nil o
--- "" saca el alias y vuelve a mostrar la ruta.
function M.rename(path, name)
  local abs = normalize(path)
  local data = read_all()
  for _, entry in ipairs(data) do
    if entry.path == abs then
      entry.name = (name and name ~= "") and name or nil
      break
    end
  end
  write_all(data)
end

function M.remove(path)
  local abs = normalize(path)
  local data = read_all()
  for i, entry in ipairs(data) do
    if entry.path == abs then
      table.remove(data, i)
      break
    end
  end
  write_all(data)
end

function M.start_watch()
  local group = vim.api.nvim_create_augroup("ProjectsRecent", { clear = true })
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = function()
      M.record(vim.fn.getcwd())
    end,
  })
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      M.record(vim.fn.getcwd())
    end,
  })
end

return M
