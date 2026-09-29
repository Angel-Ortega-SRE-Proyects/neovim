local previous = package.loaded["config.i18n"]
local M = type(previous) == "table" and previous or {}

M.languages = { es = "Español", en = "English" }
M.translations = {
  es = {
    ["AGENT HUB"] = "CENTRO DE AGENTES",
    ["Agent Hub"] = "Centro de agentes",
    ["GIT HUB"] = "CENTRO GIT",
    ["CAMBIOS"] = "CAMBIOS",
    ["PROYECTOS REGISTRADOS"] = "PROYECTOS REGISTRADOS",
    ["NUEVA INSTANCIA"] = "NUEVA INSTANCIA",
    ["ARCHIVOS MODIFICADOS"] = "ARCHIVOS MODIFICADOS",
    ["ACCIONES"] = "ACCIONES",
    ["AGENTES DEL PROYECTO"] = "AGENTES DEL PROYECTO",
    ["PERFILES ACTIVOS"] = "PERFILES ACTIVOS",
    ["AGENTES REGISTRADOS"] = "AGENTES REGISTRADOS",
    ["PROJECT"] = "PROYECTO",
    ["ACTIVE"] = "ACTIVOS",
    ["No active agents"] = "Sin agentes activos",
    ["No se pudo construir el índice de comandos."] = "No se pudo construir el índice de comandos.",
  },
  en = {
    ["AGENT HUB"] = "AGENT HUB",
    ["Agent Hub"] = "Agent Hub",
    ["GIT HUB"] = "GIT HUB",
    ["CAMBIOS"] = "CHANGES",
    ["PROYECTOS REGISTRADOS"] = "REGISTERED PROJECTS",
    ["NUEVA INSTANCIA"] = "NEW INSTANCE",
    ["ARCHIVOS MODIFICADOS"] = "MODIFIED FILES",
    ["ACCIONES"] = "ACTIONS",
    ["AGENTES DEL PROYECTO"] = "PROJECT AGENTS",
    ["PERFILES ACTIVOS"] = "ACTIVE PROFILES",
    ["AGENTES REGISTRADOS"] = "REGISTERED AGENTS",
    ["PROJECT"] = "PROJECT",
    ["ACTIVE"] = "ACTIVE",
    ["No active agents"] = "No active agents",
    ["No se pudo construir el índice de comandos."] = "Could not build the command index.",
  },
}

local common = {
  ["Configuración recargada: "] = { es = "Configuración recargada: ", en = "Configuration reloaded: " },
  ["Recargar la configuración de Neovim"] = { es = "Recargar la configuración de Neovim", en = "Reload Neovim configuration" },
  ["Seleccionar idioma"] = { es = "Seleccionar idioma", en = "Select language" },
  ["Idioma"] = { es = "Idioma", en = "Language" },
  ["Idiomas disponibles"] = { es = "Idiomas disponibles", en = "Available languages" },
  ["j/k o ↑/↓ · Enter aplicar · q/Esc cancelar"] = { es = "j/k o ↑/↓ · Enter aplicar · q/Esc cancelar", en = "j/k or ↑/↓ · Enter apply · q/Esc cancel" },
  ["activo"] = { es = "activo", en = "active" },
  ["sí"] = { es = "sí", en = "yes" },
  ["no"] = { es = "no", en = "no" },
  ["Proyecto registrado"] = { es = "Proyecto registrado", en = "Registered project" },
  ["Nombre:"] = { es = "Nombre:", en = "Name:" },
  ["Ruta:"] = { es = "Ruta:", en = "Path:" },
  ["Rama:"] = { es = "Rama:", en = "Branch:" },
  ["Último acceso:"] = { es = "Último acceso:", en = "Last access:" },
  ["Cambios:"] = { es = "Cambios:", en = "Changes:" },
  ["Fijo:"] = { es = "Fijo:", en = "Pinned:" },
  ["Estado:"] = { es = "Estado:", en = "Status:" },
  ["Descripción:"] = { es = "Descripción:", en = "Description:" },
  ["Abrir proyecto"] = { es = "Abrir proyecto", en = "Open project" },
  ["Agentes del proyecto"] = { es = "Agentes del proyecto", en = "Project agents" },
  ["Enter  abrir proyecto"] = { es = "Enter  abrir proyecto", en = "Enter  open project" },
  ["p  abrir proyecto"] = { es = "p  abrir proyecto", en = "p  open project" },
  ["Enter  listar agentes y estados"] = { es = "Enter  listar agentes y estados", en = "Enter  list agents and status" },
  ["Atajos:"] = { es = "Atajos:", en = "Shortcuts:" },
  ["Comando del agente"] = { es = "Comando del agente", en = "Agent command" },
  ["Agente:"] = { es = "Agente:", en = "Agent:" },
  ["Comando:"] = { es = "Comando:", en = "Command:" },
  ["Proyecto:"] = { es = "Proyecto:", en = "Project:" },
  ["Sesión "] = { es = "Sesión ", en = "Session " },
  ["Título:"] = { es = "Título:", en = "Title:" },
  ["ID:"] = { es = "ID:", en = "ID:" },
  ["Enter  reanudar sesión"] = { es = "Enter  reanudar sesión", en = "Enter  resume session" },
  ["Repositorio"] = { es = "Repositorio", en = "Repository" },
  ["Repo activo:"] = { es = "Repo activo:", en = "Active repo:" },
  ["Sin archivos modificados"] = { es = "Sin archivos modificados", en = "No modified files" },
  ["La carpeta no es un repositorio Git"] = { es = "La carpeta no es un repositorio Git", en = "Folder is not a Git repository" },
  ["Sin agentes activos"] = { es = "Sin agentes activos", en = "No active agents" },
  ["Sin agentes registrados en este proyecto"] = { es = "Sin agentes registrados en este proyecto", en = "No agents registered in this project" },
  ["comando:"] = { es = "comando:", en = "command:" },
  ["volver a proyectos"] = { es = "volver a proyectos", en = "back to projects" },
  ["volver al proyecto"] = { es = "volver al proyecto", en = "back to project" },
  ["sesiones"] = { es = "sesiones", en = "sessions" },
  ["repositorio(s)"] = { es = "repositorio(s)", en = "repository/repositories" },
  ["repositorios"] = { es = "repositorios", en = "repositories" },
  ["listo"] = { es = "listo", en = "ready" },
  ["detenido"] = { es = "detenido", en = "stopped" },
  ["ejecutando"] = { es = "ejecutando", en = "running" },
  ["oculto"] = { es = "oculto", en = "hidden" },
  ["Proyecto"] = { es = "Proyecto", en = "Project" },
  ["Cambios"] = { es = "Cambios", en = "Changes" },
  ["Abrir"] = { es = "Abrir", en = "Open" },
  ["Fijar/Repos"] = { es = "Fijar/Repos", en = "Pin/Repos" },
  ["Nueva"] = { es = "Nueva", en = "New" },
  ["Renombrar"] = { es = "Renombrar", en = "Rename" },
  ["Detener"] = { es = "Detener", en = "Stop" },
  ["Expandir"] = { es = "Expandir", en = "Expand" },
  ["abrir agente"] = { es = "abrir agente", en = "open agent" },
  ["nueva instancia"] = { es = "nueva instancia", en = "new instance" },
  ["Elige una sesión en el panel izquierdo para comenzar."] = { es = "Elige una sesión en el panel izquierdo para comenzar.", en = "Choose a session in the left panel to begin." },
  ["La terminal no se inicia hasta que tú la selecciones."] = { es = "La terminal no se inicia hasta que tú la selecciones.", en = "The terminal will not start until you select it." },
  ["CONTROL DE REPOSITORIO"] = { es = "CONTROL DE REPOSITORIO", en = "REPOSITORY CONTROL" },
  ["Historial de commits"] = { es = "Historial de commits", en = "Commit history" },
  ["Ramas y checkout       <C-o>"] = { es = "Ramas y checkout       <C-o>", en = "Branches and checkout  <C-o>" },
  ["Estado y cambios"] = { es = "Estado y cambios", en = "Status and changes" },
  ["Diff de cambios"] = { es = "Diff de cambios", en = "Changes diff" },
  ["Historial del repositorio"] = { es = "Historial del repositorio", en = "Repository history" },
  ["Stage del archivo actual"] = { es = "Stage del archivo actual", en = "Stage current file" },
  ["Actualizar Git Hub"] = { es = "Actualizar Git Hub", en = "Refresh Git Hub" },
  ["Cerrar Git Hub"] = { es = "Cerrar Git Hub", en = "Close Git Hub" },
  ["Repositorio:"] = { es = "Repositorio:", en = "Repository:" },
  ["Enter ejecutar   ·   r actualizar   ·   q cerrar"] = { es = "Enter ejecutar   ·   r actualizar   ·   q cerrar", en = "Enter run   ·   r refresh   ·   q close" },
  ["Esc / :GitBack volver al menú desde cualquier vista"] = { es = "Esc / :GitBack volver al menú desde cualquier vista", en = "Esc / :GitBack return to the menu from any view" },
  ["No estás dentro de un repositorio Git"] = { es = "No estás dentro de un repositorio Git", en = "You are not inside a Git repository" },
  ["Sin diff disponible: el archivo es nuevo o no está seguido por Git."] = { es = "Sin diff disponible: el archivo es nuevo o no está seguido por Git.", en = "No diff available: the file is new or is not tracked by Git." },
  ["Centro de agentes"] = { es = "Centro de agentes", en = "Agent Hub" },
  ["Búsqueda (Telescope)"] = { es = "Búsqueda (Telescope)", en = "Search (Telescope)" },
  ["Cambios de Git (gitsigns)"] = { es = "Cambios de Git (gitsigns)", en = "Git changes (gitsigns)" },
  ["Lista de diagnósticos/LSP"] = { es = "Lista de diagnósticos/LSP", en = "Diagnostics/LSP list" },
  ["Búfer anterior"] = { es = "Búfer anterior", en = "Previous buffer" },
  ["Búfer siguiente"] = { es = "Búfer siguiente", en = "Next buffer" },
  ["Limpiar resaltado de búsqueda"] = { es = "Limpiar resaltado de búsqueda", en = "Clear search highlight" },
  ["Cambiar tema de colores"] = { es = "Cambiar tema de colores", en = "Change color theme" },
  ["Buscar archivos"] = { es = "Buscar archivos", en = "Find files" },
  ["Buscar texto (búsqueda en vivo)"] = { es = "Buscar texto (búsqueda en vivo)", en = "Live text search" },
  ["Archivos recientes"] = { es = "Archivos recientes", en = "Recent files" },
  ["Carpetas recientes"] = { es = "Carpetas recientes", en = "Recent folders" },
  ["Explorador de archivos"] = { es = "Explorador de archivos", en = "File explorer" },
  ["Nuevo archivo"] = { es = "Nuevo archivo", en = "New file" },
  ["Salir"] = { es = "Salir", en = "Quit" },
  ["Buscar y abrir archivos"] = { es = "Buscar y abrir archivos", en = "Find and open files" },
  ["Buscar texto (carpeta actual)"] = { es = "Buscar texto (carpeta actual)", en = "Search text (current folder)" },
  ["Búferes abiertos"] = { es = "Búferes abiertos", en = "Open buffers" },
  ["Buscar SOLO en el archivo abierto"] = { es = "Buscar SOLO en el archivo abierto", en = "Search ONLY in the open file" },
  ["Siguiente cambio"] = { es = "Siguiente cambio", en = "Next change" },
  ["Cambio anterior"] = { es = "Cambio anterior", en = "Previous change" },
  ["Preparar cambio"] = { es = "Preparar cambio", en = "Stage change" },
  ["Restablecer cambio"] = { es = "Restablecer cambio", en = "Reset change" },
  ["Preparar cambio (selección)"] = { es = "Preparar cambio (selección)", en = "Stage change (selection)" },
  ["Restablecer cambio (selección)"] = { es = "Restablecer cambio (selección)", en = "Reset change (selection)" },
  ["Preparar todo el archivo"] = { es = "Preparar todo el archivo", en = "Stage entire file" },
  ["Restablecer todo el archivo"] = { es = "Restablecer todo el archivo", en = "Reset entire file" },
  ["Vista previa del cambio"] = { es = "Vista previa del cambio", en = "Preview change" },
  ["Autoría de la línea"] = { es = "Autoría de la línea", en = "Line blame" },
  ["Ir a la definición"] = { es = "Ir a la definición", en = "Go to definition" },
  ["Ir a las referencias"] = { es = "Ir a las referencias", en = "Go to references" },
  ["Mostrar documentación"] = { es = "Mostrar documentación", en = "Show documentation" },
  ["Renombrar símbolo"] = { es = "Renombrar símbolo", en = "Rename symbol" },
  ["Diagnóstico flotante"] = { es = "Diagnóstico flotante", en = "Floating diagnostic" },
  ["Mostrar/ocultar explorador"] = { es = "Mostrar/ocultar explorador", en = "Show/hide file explorer" },
  ["Alternar archivos ocultos"] = { es = "Alternar archivos ocultos", en = "Toggle hidden files" },
  ["Diagnósticos (espacio de trabajo)"] = { es = "Diagnósticos (espacio de trabajo)", en = "Diagnostics (workspace)" },
  ["Diagnósticos (buffer actual)"] = { es = "Diagnósticos (buffer actual)", en = "Diagnostics (current buffer)" },
  ["Lista de correcciones rápidas"] = { es = "Lista de correcciones rápidas", en = "Quickfix list" },
  ["Monitor del sistema (top)"] = { es = "Monitor del sistema (top)", en = "System monitor (top)" },
  ["Vista previa Markdown (navegador, con Mermaid)"] = { es = "Vista previa Markdown (navegador, con Mermaid)", en = "Markdown preview (browser, with Mermaid)" },
  ["Detener vista previa Markdown"] = { es = "Detener vista previa Markdown", en = "Stop Markdown preview" },
  ["Ir a división/panel izquierdo (flecha)"] = { es = "Ir a división/panel izquierdo (flecha)", en = "Go to left split/panel (arrow)" },
  ["Ir a división/panel inferior (flecha)"] = { es = "Ir a división/panel inferior (flecha)", en = "Go to lower split/panel (arrow)" },
  ["Ir a división/panel superior (flecha)"] = { es = "Ir a división/panel superior (flecha)", en = "Go to upper split/panel (arrow)" },
  ["Ir a división/panel derecho (flecha)"] = { es = "Ir a división/panel derecho (flecha)", en = "Go to right split/panel (arrow)" },
  ["Cambiar idioma de la interfaz"] = { es = "Cambiar idioma de la interfaz", en = "Change interface language" },
  ["Interfaz"] = { es = "Interfaz", en = "Interface" },
  ["Terminal"] = { es = "Terminal", en = "Terminal" },
  ["Proyectos"] = { es = "Proyectos", en = "Projects" },
  ["Markdown"] = { es = "Markdown", en = "Markdown" },
  ["Sesión (persistence)"] = { es = "Sesión (persistence)", en = "Session (persistence)" },
  ["Git / Copilot"] = { es = "Git / Copilot", en = "Git / Copilot" },
  ["Abrir modo Git"] = { es = "Abrir modo Git", en = "Open Git mode" },
  ["Abrir GitHub Copilot"] = { es = "Abrir GitHub Copilot", en = "Open GitHub Copilot" },
  ["Tema · elegir"] = { es = "Tema · elegir", en = "Theme · choose" },
  ["Temas disponibles"] = { es = "Temas disponibles", en = "Available themes" },
  ["j/k o ↑/↓ · Enter aplicar · 1-8 elegir · q/Esc cancelar"] = { es = "j/k o ↑/↓ · Enter aplicar · 1-8 elegir · q/Esc cancelar", en = "j/k or ↑/↓ · Enter apply · 1-8 choose · q/Esc cancel" },
  ["Recargar la paleta del tema"] = { es = "Recargar la paleta del tema", en = "Reload theme palette" },
  ["Seleccionar paleta de colores"] = { es = "Seleccionar paleta de colores", en = "Select color palette" },
  ["GIT HUB  ·  CAMBIOS  ·  "] = { es = "CENTRO GIT  ·  CAMBIOS  ·  ", en = "GIT HUB  ·  CHANGES  ·  " },
  ["  Repo activo:"] = { es = "  Repo activo:", en = "  Active repo:" },
  ["archivo(s) modificado(s)"] = { es = "archivo(s) modificado(s)", en = "file(s) modified" },
  ["plegado"] = { es = "plegado", en = "collapsed" },
  ["AGENT HUB  ·  sesiones"] = { es = "CENTRO DE AGENTES  ·  sesiones", en = "AGENT HUB  ·  sessions" },
  ["PROYECTO  ·  "] = { es = "PROYECTO  ·  ", en = "PROJECT  ·  " },
  ["AGENTES  ·  "] = { es = "AGENTES  ·  ", en = "AGENTS  ·  " },
  ["TERMINAL  ·  auxiliar"] = { es = "TERMINAL  ·  auxiliar", en = "TERMINAL  ·  auxiliary" },
  ["DIFF  ·  "] = { es = "DIFF  ·  ", en = "DIFF  ·  " },
  ["BIENVENIDO"] = { es = "BIENVENIDO", en = "WELCOME" },
  ["Selecciona uno o varios repositorios (Space/Enter marca):"] = { es = "Selecciona uno o varios repositorios (Space/Enter marca):", en = "Select one or more repositories (Space/Enter toggles):" },
  ["agregar repositorio"] = { es = "agregar repositorio", en = "add repository" },
  ["volver a cambios"] = { es = "volver a cambios", en = "back to changes" },
  ["actualizar diff"] = { es = "actualizar diff", en = "refresh diff" },
}

for key, value in pairs(common) do
  M.translations.es[key] = value.es
  M.translations.en[key] = value.en
end

M.lang = M.lang or "es"
M.path = M.path or (vim.fn.stdpath("data") .. "/nvim-language")

local function escape_pattern(text)
  return (text:gsub("([^%w])", "%%%1"))
end

function M.t(key)
  return M.translations[M.lang][key] or key
end

function M.translate_line(line)
  local translations = M.translations[M.lang]
  local keys = vim.tbl_keys(translations)
  table.sort(keys, function(left, right) return #left > #right end)
  for _, key in ipairs(keys) do
    local value = translations[key]
    line = line:gsub(escape_pattern(key), value)
  end
  return line
end

function M.translate_lines(lines)
  return vim.tbl_map(M.translate_line, lines)
end

local function load_saved_language()
  local ok, saved = pcall(vim.fn.readfile, M.path, "b")
  local language = ok and saved[1] and vim.trim(saved[1]) or "es"
  M.lang = M.languages[language] and language or "es"
end

local function save_language(language)
  vim.fn.mkdir(vim.fn.stdpath("data"), "p")
  pcall(vim.fn.writefile, { language }, M.path)
end

function M.set(language)
  if not M.languages[language] then
    vim.notify("Idioma no disponible: " .. language, vim.log.levels.WARN)
    return false
  end
  M.lang = language
  save_language(language)
  if vim.fn.exists(":ConfigReload") == 2 then vim.cmd("ConfigReload") end
  return true
end

function M.select()
  local names = { "es", "en" }
  local current = M.lang == "en" and 2 or 1
  local width = math.min(math.max(44, math.floor(vim.o.columns * 0.45)), vim.o.columns - 4)
  local height = math.min(#names + 4, vim.o.lines - 4)
  local buffer = vim.api.nvim_create_buf(false, true)
  local window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor", width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2 - 1),
    col = math.floor((vim.o.columns - width) / 2), style = "minimal", border = "rounded",
    title = " " .. M.t("Idioma") .. " ", title_pos = "center",
  })
  local function close()
    if vim.api.nvim_win_is_valid(window) then vim.api.nvim_win_close(window, true) end
    if vim.api.nvim_buf_is_valid(buffer) then vim.api.nvim_buf_delete(buffer, { force = true }) end
  end
  local function render()
    local lines = { "  " .. M.t("Idiomas disponibles"), "  " .. M.t("j/k o ↑/↓ · Enter aplicar · q/Esc cancelar"), "" }
    for index, language in ipairs(names) do
      local marker = index == current and "●" or " "
      local active = language == M.lang and "  " .. M.t("activo") or ""
      lines[#lines + 1] = string.format(" %s %d  %-10s%s", marker, index, M.languages[language], active)
    end
    vim.bo[buffer].modifiable = true
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.bo[buffer].modifiable = false
    vim.api.nvim_win_set_cursor(window, { current + 3, 0 })
  end
  local function choose(index)
    if not names[index] then return end
    close()
    M.set(names[index])
  end
  vim.bo[buffer].buftype, vim.bo[buffer].bufhidden = "nofile", "wipe"
  vim.wo[window].cursorline, vim.wo[window].wrap = true, false
  local opts = { buffer = buffer, nowait = true, silent = true }
  for _, key in ipairs({ "j", "<Down>" }) do vim.keymap.set("n", key, function() current = current % #names + 1; render() end, opts) end
  for _, key in ipairs({ "k", "<Up>" }) do vim.keymap.set("n", key, function() current = (current - 2) % #names + 1; render() end, opts) end
  vim.keymap.set("n", "<CR>", function() choose(current) end, opts)
  vim.keymap.set("n", "q", close, opts)
  vim.keymap.set("n", "<Esc>", close, opts)
  render()
end

load_saved_language()
vim.api.nvim_create_user_command("LanguageSelect", M.select, { desc = M.t("Seleccionar idioma"), force = true })
vim.api.nvim_create_user_command("LanguageSet", function(args) M.set(args.args) end, {
  nargs = 1, complete = function() return { "es", "en" } end,
  desc = M.t("Seleccionar idioma"), force = true,
})

return M
