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

local function display_name(entry)
  return entry.name or vim.fn.fnamemodify(entry.path, ":t")
end

function M.name_for(path)
  local abs = normalize(path)
  for _, entry in ipairs(M.list()) do
    if entry.path == abs then
      return display_name(entry)
    end
  end
  return vim.fn.fnamemodify(abs, ":t")
end

function M.open(path)
  local abs = normalize(path)
  if vim.fn.isdirectory(abs) ~= 1 then
    vim.notify("No es una carpeta: " .. abs, vim.log.levels.WARN)
    return false
  end

  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    local ok, tab_path = pcall(vim.api.nvim_tabpage_get_var, tabpage, "project_path")
    if ok and tab_path == abs then
      vim.api.nvim_set_current_tabpage(tabpage)
      return true
    end
  end

  vim.cmd("tabnew")
  vim.cmd.tcd(vim.fn.fnameescape(abs))
  M.record(abs)
  M.mark_current(abs)
  pcall(vim.cmd, "NvimTreeOpen")
  return true
end

local function tab_title(tabpage, tabnr)
  local ok_hub, is_hub = pcall(vim.api.nvim_tabpage_get_var, tabpage, "agent_hub")
  if ok_hub and is_hub then
    return "Agent Hub"
  end
  local ok_name, name = pcall(vim.api.nvim_tabpage_get_var, tabpage, "project_name")
  if ok_name and name and name ~= "" then
    return name
  end
  return vim.fn.fnamemodify(vim.fn.getcwd(-1, tabnr), ":t")
end

--- Lista de { path, last } ordenada por más reciente primero.
function M.list()
  local data = read_all()
  table.sort(data, function(a, b) return (a.last or 0) > (b.last or 0) end)
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

  table.sort(data, function(a, b) return (a.last or 0) > (b.last or 0) end)
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
  local label = name and name ~= "" and name or vim.fn.fnamemodify(abs, ":t")
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    local ok, tab_path = pcall(vim.api.nvim_tabpage_get_var, tabpage, "project_path")
    if ok and tab_path == abs then
      vim.api.nvim_tabpage_set_var(tabpage, "project_name", label)
    end
  end
  M.refresh_tabs()
end

function M.mark_current(path)
  local tabpage = vim.api.nvim_get_current_tabpage()
  local has_hub, is_hub = pcall(vim.api.nvim_tabpage_get_var, tabpage, "agent_hub")
  if has_hub and is_hub then
    return
  end
  local abs = normalize(path)
  local entry
  for _, candidate in ipairs(M.list()) do
    if candidate.path == abs then
      entry = candidate
      break
    end
  end
  local label = entry and display_name(entry) or vim.fn.fnamemodify(abs, ":t")
  vim.api.nvim_tabpage_set_var(tabpage, "project_path", abs)
  vim.api.nvim_tabpage_set_var(tabpage, "project_name", label)
  M.refresh_tabs()
end

function M.current_name()
  local ok, name = pcall(vim.api.nvim_tabpage_get_var, 0, "project_name")
  return ok and name or nil
end

function M.refresh_tabs()
  for tabnr, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    local title = tab_title(tabpage, tabnr)
    vim.api.nvim_tabpage_set_var(tabpage, "name", string.format("%d · %s", tabnr, title))
  end
  pcall(vim.cmd.redrawtabline)
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
  vim.api.nvim_create_autocmd({ "TabNew", "TabEnter", "TabClosed" }, {
    group = group,
    callback = function()
      vim.schedule(M.refresh_tabs)
    end,
  })
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = function()
      local cwd = vim.fn.getcwd()
      M.record(cwd)
      M.mark_current(cwd)
    end,
  })
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      local cwd = vim.fn.getcwd()
      M.record(cwd)
      M.mark_current(cwd)
    end,
  })
end

return M
