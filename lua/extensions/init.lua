-- Sistema de extensiones: permite sumar configuración a esta instalación de
-- Neovim sin editar los módulos base. Cada archivo en
-- lua/extensions/enabled/*.lua (ver _example.lua) devuelve una tabla:
--
--   return {
--     name = "mi-extension",
--     description = "opcional",
--     setup = function(api) ... end,
--   }
--
-- `api` ofrece:
--   api.contribute(point, value)  aporta datos a un punto de extensión
--   api.on(event, fn)             escucha un evento (M.emit lo dispara)
--
-- Puntos de extensión que este módulo aplica solo:
--   "i18n.translations"  { [clave_es] = { es = "...", en = "..." } }
--   "which_key.spec"     lista de specs de which-key (grupos / desc)
-- Puntos que los módulos base consultan con M.contributions(point):
--   "git_hub.actions"    lista de { label, fn } para el menú Git Hub
--
-- Una extensión con error no rompe el arranque: se aísla con pcall y queda
-- registrada en M.errors() / :Extensions.
local M = {}

local state = { extensions = {}, contributions = {}, handlers = {}, errors = {} }

local function reset()
  state = { extensions = {}, contributions = {}, handlers = {}, errors = {} }
end

local function fail(name, err)
  state.errors[#state.errors + 1] = { name = name, error = tostring(err) }
  vim.notify(("Extensión '%s': %s"):format(name, tostring(err)), vim.log.levels.WARN)
end

local function apply_i18n(translations)
  local ok, i18n = pcall(require, "config.i18n")
  if not ok then return end
  for key, value in pairs(translations) do
    if type(value) == "table" then
      for lang, text in pairs(value) do
        if i18n.translations[lang] then i18n.translations[lang][key] = text end
      end
    end
  end
end

local function apply_which_key(spec)
  local ok, wk = pcall(require, "which-key")
  if ok then pcall(wk.add, spec) end
end

local APPLIERS = {
  ["i18n.translations"] = apply_i18n,
  ["which_key.spec"] = apply_which_key,
}

local function make_api(name)
  return {
    contribute = function(point, value)
      local list = state.contributions[point] or {}
      list[#list + 1] = { source = name, value = value }
      state.contributions[point] = list
      local applier = APPLIERS[point]
      if applier then
        local ok, err = pcall(applier, value)
        if not ok then fail(name, err) end
      end
    end,
    on = function(event, fn)
      local list = state.handlers[event] or {}
      list[#list + 1] = { source = name, fn = fn }
      state.handlers[event] = list
    end,
  }
end

function M.register(spec)
  if type(spec) ~= "table" or type(spec.name) ~= "string" or spec.name == "" then
    fail("?", "la extensión necesita un `name` (string)")
    return false
  end
  if state.extensions[spec.name] then
    fail(spec.name, "nombre duplicado")
    return false
  end
  state.extensions[spec.name] = spec
  if type(spec.setup) == "function" then
    local ok, err = pcall(spec.setup, make_api(spec.name))
    if not ok then fail(spec.name, err) end
  end
  return true
end

-- Carpetas externas con extensiones propias (fuera de este repo). Cada raíz
-- tiene la misma forma que el runtimepath: lua/extensions/enabled/*.lua y,
-- opcionalmente, sus módulos de apoyo en lua/<nombre>/. Se configura con
-- vim.g.extension_roots (lista de rutas) antes de arrancar.
local DEFAULT_ROOTS = { "~/Documentos/Proyects/settings/nvim-personal" }

local function existing_roots()
  local roots = {}
  for _, root in ipairs(vim.g.extension_roots or DEFAULT_ROOTS) do
    root = vim.fn.expand(root)
    if vim.fn.isdirectory(root) == 1 then roots[#roots + 1] = root end
  end
  return roots
end

local function add_roots()
  for _, root in ipairs(existing_roots()) do
    if not vim.tbl_contains(vim.opt.rtp:get(), root) then vim.opt.rtp:append(root) end
    -- Permite require("<extensión>.<módulo>") sobre <root>/<extensión>/<módulo>.lua.
    local patterns = root .. "/?.lua;" .. root .. "/?/init.lua"
    if not package.path:find(patterns, 1, true) then package.path = patterns .. ";" .. package.path end
  end
end

-- Extensiones en carpeta propia: <root>/<nombre>/extension.lua, con todos sus
-- módulos de apoyo dentro de esa misma carpeta. Se cargan por ruta (loadfile)
-- para que :ConfigReload siempre lea el archivo actual, y se limpian sus
-- módulos de package.loaded para que las ediciones se recojan al recargar.
local function load_folder_extensions()
  for _, root in ipairs(existing_roots()) do
    for _, path in ipairs(vim.fn.glob(root .. "/*/extension.lua", false, true)) do
      local dir = vim.fn.fnamemodify(path, ":h:t")
      if not vim.startswith(dir, "_") then
        for module in pairs(package.loaded) do
          if module == dir or vim.startswith(module, dir .. ".") then package.loaded[module] = nil end
        end
        local chunk, err = loadfile(path)
        local ok, spec = false, err
        if chunk then ok, spec = pcall(chunk) end
        if ok then M.register(spec) else fail(dir, spec) end
      end
    end
  end
end

local function module_names()
  local names, seen = {}, {}
  for _, path in ipairs(vim.api.nvim_get_runtime_file("lua/extensions/enabled/*.lua", true)) do
    local real = vim.uv.fs_realpath(path) or path
    local file = vim.fn.fnamemodify(path, ":t:r")
    -- El mismo archivo puede aparecer por dos entradas del runtimepath
    -- (p. ej. symlink de ~/.config/nvim): cargarlo una sola vez.
    if not seen[real] and not vim.startswith(file, "_") then
      seen[real] = true
      names[#names + 1] = file
    end
  end
  table.sort(names)
  return names
end

-- Descubre y carga todo lo que haya en extensions/enabled. Idempotente:
-- se puede volver a llamar (p. ej. desde :ConfigReload) y rehace el estado.
function M.load()
  reset()
  add_roots()
  for _, file in ipairs(module_names()) do
    local module = "extensions.enabled." .. file
    package.loaded[module] = nil
    local ok, spec = pcall(require, module)
    if ok then
      M.register(spec)
    else
      fail(file, spec)
    end
  end
  load_folder_extensions()
  M.emit("loaded")
end

-- Aportes de todas las extensiones a un punto, en orden de carga.
function M.contributions(point)
  local values = {}
  for _, item in ipairs(state.contributions[point] or {}) do
    values[#values + 1] = item.value
  end
  return values
end

function M.emit(event, ...)
  for _, handler in ipairs(state.handlers[event] or {}) do
    local ok, err = pcall(handler.fn, ...)
    if not ok then fail(handler.source, err) end
  end
end

function M.list()
  local names = vim.tbl_keys(state.extensions)
  table.sort(names)
  return vim.tbl_map(function(name) return state.extensions[name] end, names)
end

function M.errors()
  return state.errors
end

vim.api.nvim_create_user_command("Extensions", function()
  local lines = {}
  for _, ext in ipairs(M.list()) do
    lines[#lines + 1] = ("• %s%s"):format(ext.name, ext.description and (" — " .. ext.description) or "")
  end
  for _, e in ipairs(M.errors()) do
    lines[#lines + 1] = ("✗ %s: %s"):format(e.name, e.error)
  end
  if #lines == 0 then lines[1] = "Sin extensiones cargadas (lua/extensions/enabled/)" end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end, { desc = "Listar extensiones cargadas", force = true })

return M
