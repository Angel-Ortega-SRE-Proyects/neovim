-- CLIs de IA agéntica (Claude Code, Codex, OpenCode). A diferencia de
-- Copilot (ver lua/plugins/copilot.lua, autocompletado ghost-text inline),
-- estas son herramientas de terminal.
--
-- Cada una vive en una ventana FLOTANTE que se togglea (mismo patrón que
-- :Sys en terminal.lua): el proceso queda corriendo en segundo plano en su
-- buffer aunque cierres la ventana, así que podés tener Claude Y Codex
-- corriendo los dos a la vez y saltar entre ellos con una tecla, sin tocar
-- tu layout de splits/tmux -- al ocultar volvés exactamente a donde estabas.
--
-- Uso:
--   <leader>ac   Mostrar/ocultar Claude Code
--   <leader>ax   Mostrar/ocultar Codex
--   <leader>ao   Mostrar/ocultar OpenCode
--   <leader>ag   Mostrar/ocultar Gemini
--   <leader>aC   Mostrar/ocultar GitHub Copilot CLI (:CopilotCli -- "Copilot"
--                a secas ya lo usa zbirenbaum/copilot.lua, la ghost-text)
--   q  (dentro del flotante, en modo normal)   también lo oculta
--   Alt-q / Alt-d / Alt-k   ocultar/diff/matar SIN salir del modo terminal
--      -- ojo con <C-d> "pelado": eso NO lo intercepta Neovim, se lo manda
--      tal cual al proceso (Claude/Codex lo pueden leer como EOF y cerrar
--      la sesión), por eso estos atajos usan Alt en vez de Ctrl.
--   Alt-a   el selector rápido de sesiones, sin salir del
--      agente en el que estás -- Alt adentro se comporta como <leader>
--      afuera.
--
--   <leader>aa   "Agent Hub": pestaña con sesiones a la izquierda, terminal
--                activa al centro y cambios Git a la derecha. Enter abre una
--                sesión; n crea otra; x la detiene; d ve su diff.
--
--   :Claude / :Codex / :OpenCode   equivalentes, con argumentos opcionales
--   (ej. :Claude --resume) que solo se usan la PRIMERA vez que se abre esa
--   herramienta (una sesión ya corriendo no se reinicia al togglear).
--   También funcionan en minúscula (:claude, :codex, :opencode).
--
--   :Claude! / :Codex! / :OpenCode!   (con "!") arrancan una INSTANCIA
--   NUEVA además de la que ya esté corriendo -- ej. dos Claude en paralelo,
--   una por tarea. Quedan como "Claude Code #2", "#3", etc. También se
--   puede desde el picker (<leader>aa): la opción "+ nueva instancia".
--
--   d  (dentro del flotante, en modo normal)   ver en Diffview SOLO los
--      archivos que ese agente tocó desde que arrancó -- se guarda una
--      foto de `git status --porcelain` al abrirlo la primera vez y se
--      compara contra el status actual, así no mezcla con cambios que ya
--      tenías sucios de antes. También <C-d> desde el picker (<leader>aa).
--
--   <leader>ad / :AgentDiff [nombre]   igual que "d" pero desde cualquier
--                lado (no hace falta estar parado en el flotante). Sin
--                argumento: si estás en el buffer de un agente usa ese, si
--                hay uno solo corriendo usa ese, si hay varios te pregunta.
--   <leader>ak / :AgentKill [nombre]   mismo criterio, pero mata el agente
--                (equivalente a <C-x> en el picker).
--
--   <leader>aw / :AgentWorkspace [nombre]   abre un espacio de trabajo a
--                pantalla completa: agente a la izquierda y cambios Git a
--                la derecha. En el panel de cambios, r lo actualiza.

local AGENTS = {
  { name = "Claude Code", cmd = "claude" },
  { name = "Codex", cmd = "codex" },
  { name = "OpenCode", cmd = "opencode" },
  { name = "Gemini", cmd = "gemini" },
  { name = "Copilot", cmd = "copilot" },
}
local codex_sessions = require("config.codex_sessions")

local state = {} -- name -> { buf, win }
local is_shutting_down = false
local function valid_buf(buf)
  return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end
-- forward-declarados: toggle_tool los referencia (en los binds Alt-k/Alt-a)
-- antes de que se definan más abajo en el archivo.
local open_agents_picker
local open_agent_hub
local close_agent_hub
local stop_agent
local toggle_tool
local start_new_instance
local agent_status
local STATUS_ICON
local create_agent_hub_welcome
local agent_hub = {}
local layout_agent_hub
local refresh_hub_changes
local map_hub_navigation
local refresh_hub_command_bar
local open_hub_repo_menu

local function session_is_visible(session)
  return session
    and session.buf
    and valid_buf(session.buf)
    and session.win
    and vim.api.nvim_win_is_valid(session.win)
    and vim.api.nvim_win_get_buf(session.win) == session.buf
end

-- Empuja los conteos a config/agents_status.lua para que la statusline
-- pinte el indicador (●N visibles, ○N ocultos) sin tener que importar todo
-- este archivo. Se llama en cada mutación de `state`.
local function publish_status()
  local visible, hidden = 0, 0
  for _, s in pairs(state) do
    if session_is_visible(s) then
      visible = visible + 1
    else
      hidden = hidden + 1
    end
  end
  require("config.agents_status").set(visible, hidden)
end

local function next_instance_name(base)
  if not state[base] then
    return base
  end
  local n = 2
  while state[base .. " #" .. n] do
    n = n + 1
  end
  return base .. " #" .. n
end

-- Set de archivos con cambios sin commitear (rutas relativas al repo), o
-- nil si el cwd actual no es un repo git.
local function dirty_files_set()
  local ok, git = pcall(require, "config.git")
  if not ok or not git.in_repo() then
    return nil
  end
  local set = {}
  for _, line in ipairs(vim.fn.systemlist({ "git", "status", "--porcelain" })) do
    local file = line:sub(4)
    file = file:match("%-> (.+)$") or file -- "old -> new" en renames: quedate con el nuevo
    set[file] = true
  end
  return set
end

-- Diffview con SOLO lo que cambió desde que este agente arrancó (dirty_at -
-- dirty_before), no todo el working tree.
local function show_agent_diff(name)
  local s = state[name]
  local now = dirty_files_set()
  if now == nil then
    vim.notify("No estás dentro de un repositorio git (" .. vim.fn.getcwd() .. ")", vim.log.levels.WARN)
    return
  end

  local before = (s and s.dirty_before) or {}
  local changed = {}
  for file in pairs(now) do
    if not before[file] then
      table.insert(changed, vim.fn.fnameescape(file))
    end
  end

  if #changed == 0 then
    vim.notify(name .. ": sin cambios nuevos desde que arrancó (o son archivos que ya estaban sucios antes)", vim.log.levels.INFO)
    return
  end

  vim.cmd("DiffviewOpen -- " .. table.concat(changed, " "))
end

local function float_opts(name)
  local width = math.floor(vim.o.columns * 0.85)
  local height = math.floor(vim.o.lines * 0.85)
  return {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = string.format(" %s (Alt-q ocultar, Alt-d diff, Alt-k matar) ", name),
    title_pos = "center",
  }
end

local function close_changes_panel(s)
  if s.changes_win and vim.api.nvim_win_is_valid(s.changes_win) then
    if #vim.api.nvim_list_wins() > 1 then
      vim.api.nvim_win_close(s.changes_win, true)
    else
      vim.api.nvim_win_set_buf(s.changes_win, vim.api.nvim_create_buf(true, false))
    end
  end
  s.changes_win = nil
end

local function git_output(root, args)
  local command = { "git", "-C", root or vim.fn.getcwd() }
  vim.list_extend(command, args)
  return vim.fn.systemlist(command)
end

-- Los objetos internos de Git nunca son archivos editables. Si una búsqueda
-- anterior dejó uno abierto, descartarlo evita E37/E162 al reconstruir el Hub.
local function discard_git_object_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local path = vim.api.nvim_buf_get_name(buf)
    if path:find("/.git/objects/", 1, true) then
      vim.bo[buf].modified = false
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
end

local function file_icon(name)
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if ok then
    local icon = devicons.get_icon(name, nil, { default = true })
    if icon then return icon end
  end
  return "󰈔"
end

local function changes_tree(files, collapsed_directories, scope)
  local root = {}
  for _, file in ipairs(files) do
    local status, path = file:sub(1, 2), file:sub(4)
    local node = root
    for part in path:gmatch("[^/]+") do
      node[part] = node[part] or {}
      node = node[part]
    end
    node.status = status
    node.path = path
  end

  local lines = { "", " ARCHIVOS MODIFICADOS" }
  local file_lines, folder_lines = {}, {}
  local function append(node, prefix, parent_path)
    local names = vim.tbl_keys(node)
    table.sort(names)
    for _, name in ipairs(names) do
      if name ~= "status" and name ~= "path" then
        local child = node[name]
        local is_file = child.status ~= nil
        if is_file then
          table.insert(lines, string.format(" %s%s %s  %s", prefix, file_icon(name), name, child.status))
          file_lines[#lines] = child.path
        else
          local directory = parent_path == "" and name or parent_path .. "/" .. name
          local collapsed = collapsed_directories[scope .. "::" .. directory]
          table.insert(lines, string.format(" %s%s %s", prefix, collapsed and "" or "", name))
          folder_lines[#lines] = directory
          if not collapsed then append(child, prefix .. "  ", directory) end
        end
      end
    end
  end
  append(root, "", "")
  return lines, file_lines, folder_lines
end

local function is_internal_change(file)
  local path = file:sub(4)
  return path:match("^%.higpertext/")
    or path:match("^%.memory/")
    or path == "nvim.log"
end

local function add_git_root(root)
  agent_hub.git_roots = agent_hub.git_roots or {}
  if not vim.tbl_contains(agent_hub.git_roots, root) then
    table.insert(agent_hub.git_roots, root)
  end
  agent_hub.git_root = root
end

local function changes_panel_lines(root)
  local roots = agent_hub.git_roots or { root or agent_hub.git_root or vim.fn.getcwd() }
  local active_root = agent_hub.git_root or roots[1]
  local lines = {
    " GIT HUB  ·  CAMBIOS",
    "",
    "  Repo activo: " .. vim.fn.fnamemodify(active_root, ":~"),
    "  g repositorios   r actualizar   c commit   Ctrl-P buscar",
    "",
  }
  local file_lines = {}
  local folder_lines = {}
  local files = git_output(active_root, { "status", "--short" })
  files = vim.tbl_filter(function(file) return not is_internal_change(file) end, files)
  if #files == 0 then
    table.insert(lines, "  Sin archivos modificados")
  else
    local tree_lines, tree_file_lines, tree_folder_lines = changes_tree(files, agent_hub.collapsed_directories or {}, active_root)
    local tree_offset = #lines
    vim.list_extend(lines, tree_lines)
    for line, path in pairs(tree_file_lines) do
      file_lines[tree_offset + line] = { root = active_root, path = path }
    end
    for line, path in pairs(tree_folder_lines) do
      folder_lines[tree_offset + line] = { root = active_root, path = path }
    end
    table.insert(lines, "")
    table.insert(lines, string.format(" %d archivo(s) modificado(s)", #files))
  end
  return lines, file_lines, folder_lines
end

local function refresh_changes_panel(buf, root)
  if type(buf) == "number" and vim.api.nvim_buf_is_valid(buf) then
    local lines, file_lines, folder_lines = changes_panel_lines(root)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.b[buf].agent_hub_changed_files = file_lines
    vim.b[buf].agent_hub_change_folders = folder_lines
  end
end

local function toggle_changes_folder(buf)
  if type(buf) ~= "number" or not vim.api.nvim_buf_is_valid(buf) then return false end
  local folders = vim.b[buf].agent_hub_change_folders
  if type(folders) ~= "table" then return false end
  local entry = folders[vim.fn.line(".")]
  if not entry then return false end
  agent_hub.collapsed_directories = agent_hub.collapsed_directories or {}
  local key = entry.root .. "::" .. entry.path
  agent_hub.collapsed_directories[key] = not agent_hub.collapsed_directories[key]
  refresh_changes_panel(buf)
  return true
end

local function create_changes_panel()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "agent-changes"
  vim.api.nvim_buf_set_name(buf, "Agent Changes " .. buf)
  refresh_changes_panel(buf)
  vim.keymap.set("n", "r", function()
    if refresh_hub_changes then
      refresh_hub_changes()
    else
      refresh_changes_panel(buf, agent_hub.git_root or vim.fn.getcwd())
    end
  end, { buffer = buf, desc = "Actualizar cambios Git" })
  return buf
end

local function agent_hub_welcome_width()
  local win = agent_hub.agent_win
  if win and vim.api.nvim_win_is_valid(win) then
    return vim.api.nvim_win_get_width(win)
  end
  return vim.o.columns
end

local function hub_welcome_buffer()
  if not valid_buf(agent_hub.welcome_buf) then
    agent_hub.welcome_buf = create_agent_hub_welcome(agent_hub_welcome_width())
  end
  return agent_hub.welcome_buf
end

-- Convierte una sesión existente (o recién iniciada) en una vista estable de
-- dos columnas, similar a chat + Changes de editores gráficos. El terminal
-- sigue siendo el mismo buffer/proceso: no reinicia ni pierde el contexto.
local function open_agent_workspace(name, cmd)
  if not state[name] then
    toggle_tool(name, cmd)
  end

  local s = state[name]
  if not s or not valid_buf(s.buf) then
    return
  end

  if s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_close(s.win, true)
  end
  close_changes_panel(s)

  local agent_win = vim.api.nvim_get_current_win()
  vim.cmd("vsplit")
  local changes_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(agent_win, s.buf)
  local changes_buf = create_changes_panel()
  vim.api.nvim_win_set_buf(changes_win, changes_buf)
  vim.cmd("wincmd =")

  s.win = agent_win
  s.changes_win = changes_win
  vim.api.nvim_set_current_win(agent_win)
  vim.cmd("startinsert")
  publish_status()
end

-- Espacio de trabajo persistente para operar agentes sin tener que recordar
-- atajos. Mantiene sesiones, terminal y cambios Git visibles a la vez.
local agent_hub_namespace = vim.api.nvim_create_namespace("agent-hub")

local function setup_agent_hub_highlights()
  local colors = require("config.theme").colors
  vim.api.nvim_set_hl(0, "AgentHubTitle", { fg = colors.green, bold = true })
  vim.api.nvim_set_hl(0, "AgentHubSection", { fg = colors.green_dim, bold = true })
  vim.api.nvim_set_hl(0, "AgentHubHint", { fg = colors.green_dim, italic = true })
  vim.api.nvim_set_hl(0, "AgentHubActive", { bg = colors.selection, fg = colors.green_bright })
  vim.api.nvim_set_hl(0, "AgentHubRunning", { fg = colors.green })
  vim.api.nvim_set_hl(0, "AgentHubStopped", { fg = colors.green_dim })
  vim.api.nvim_set_hl(0, "AgentHubAction", { fg = colors.tan })
end

local function style_agent_hub_window(win, title, is_sidebar)
  local options = vim.wo[win]
  options.number = false
  options.relativenumber = false
  options.signcolumn = "no"
  options.cursorline = is_sidebar
  options.wrap = false
  options.winbar = "  " .. title
  options.winhighlight = "CursorLine:AgentHubActive,WinBar:AgentHubSection"
end

local function choose_session_directory()
  local directory = vim.fn.input({
    prompt = "Carpeta para la sesión (Tab completa directorios): ",
    default = vim.fn.getcwd(),
    completion = "dir",
  })
  if directory == "" then return nil end
  directory = vim.fn.fnamemodify(vim.fn.expand(directory), ":p")
  if vim.fn.isdirectory(directory) ~= 1 then
    vim.notify("La carpeta de la sesión no existe", vim.log.levels.WARN)
    return nil
  end
  return directory
end

local function hub_entries()
  local entries = {}
  for _, agent in ipairs(AGENTS) do
    table.insert(entries, { name = agent.name, cmd = agent.cmd, action = "agent" })
  end
  for name, s in pairs(state) do
    if not s.external and not vim.tbl_contains(vim.tbl_map(function(agent) return agent.name end, AGENTS), name) then
      table.insert(entries, { name = name, cmd = s.cmd, action = "agent" })
    end
  end
  table.sort(entries, function(left, right) return left.name < right.name end)
  return entries, codex_sessions.grouped()
end

local function copilot_inline_status()
  local ok, copilot_status = pcall(require, "config.copilot_status")
  if not ok then return "sin iniciar" end
  local labels = {
    Normal = "listo",
    InProgress = "pensando",
    Warning = "revisar",
  }
  return labels[copilot_status.status] or "sin iniciar"
end

local function close_hub_hover()
  if agent_hub.hover_win and vim.api.nvim_win_is_valid(agent_hub.hover_win) then
    vim.api.nvim_win_close(agent_hub.hover_win, true)
  end
  agent_hub.hover_win = nil
  agent_hub.hover_buf = nil
end

local function hub_hover_lines(entry)
  if entry.action == "project" then
    return {
      "Proyecto Codex",
      "Nombre: " .. entry.display_name,
      "Ruta: " .. entry.cwd,
      "Enter / p  abrir proyecto",
    }
  end
  if entry.external then
    local status = state[entry.name] and agent_status(entry.name) or "disponible"
    return {
      "Sesión Codex",
      "Título: " .. entry.name,
      "Proyecto: " .. entry.cwd,
      "ID: " .. entry.session_id,
      "Estado: " .. status,
      "Enter  reanudar sesión",
    }
  end
  return {
    "Agente: " .. entry.name,
    "Comando: " .. entry.cmd,
    "Estado: " .. agent_status(entry.name),
  }
end

local function show_hub_hover(entry)
  close_hub_hover()
  if not entry or entry.action == "new" or not agent_hub.sidebar_win
      or not vim.api.nvim_win_is_valid(agent_hub.sidebar_win) then
    return
  end

  local lines = hub_hover_lines(entry)
  local width = 44
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line) + 2)
  end
  width = math.min(width, 86)
  local height = #lines
  local sidebar_height = vim.api.nvim_win_get_height(agent_hub.sidebar_win)
  local row = math.min(vim.fn.line(".") - 1, math.max(0, sidebar_height - height))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "win",
    win = agent_hub.sidebar_win,
    row = row,
    col = vim.api.nvim_win_get_width(agent_hub.sidebar_win) + 1,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    focusable = false,
    noautocmd = true,
    zindex = 80,
  })
  vim.wo[win].wrap = false
  vim.wo[win].winhl = "Normal:NormalFloat,FloatBorder:FloatBorder"
  agent_hub.hover_buf = buf
  agent_hub.hover_win = win
end

local function authenticate_copilot()
  local ok, err = pcall(vim.cmd, "Copilot auth")
  if not ok then
    vim.notify("No se pudo iniciar Copilot: " .. err, vim.log.levels.WARN)
  end
end

local function render_agent_hub()
  local buf = agent_hub.buf
  if not valid_buf(buf) then
    return
  end
  if layout_agent_hub then layout_agent_hub() end

  local lines = {
    "  AGENT HUB",
    "  Sesiones disponibles",
    "",
    "  SESIONES",
  }
  agent_hub.line_entries = {}
  local entries, project_groups = hub_entries()
  for _, entry in ipairs(entries) do
    local status = agent_status(entry.name)
    local selected = entry.name == agent_hub.active and ">" or " "
    local detail = entry.name == "Copilot"
        and (status .. " · inline " .. copilot_inline_status())
      or status
    table.insert(lines, string.format(" %s %s %-18s %s", selected, STATUS_ICON[status], entry.name, detail))
    agent_hub.line_entries[#lines] = entry
  end

  if #project_groups > 0 then
    table.insert(lines, "")
    table.insert(lines, "  CODEX POR PROYECTO")
    for _, group in ipairs(project_groups) do
      local project_entry = {
        name = "Codex project: " .. group.path,
        display_name = group.name,
        cwd = group.path,
        action = "project",
      }
      table.insert(lines, string.format("  ▾ %-18s %s", group.name, vim.fn.fnamemodify(group.path, ":~")))
      agent_hub.line_entries[#lines] = project_entry
      for _, session in ipairs(group.sessions) do
        local status = state[session.name] and agent_status(session.name) or "disponible"
        local selected = session.name == agent_hub.active and ">" or " "
        table.insert(lines, string.format("    %s %s %s", selected, STATUS_ICON[status], session.name))
        agent_hub.line_entries[#lines] = session
      end
    end
  end
  table.insert(lines, "")
  table.insert(lines, "  NUEVA INSTANCIA")
  for _, agent in ipairs(AGENTS) do
    table.insert(lines, " + " .. agent.name)
    agent_hub.line_entries[#lines] = { name = agent.name, cmd = agent.cmd, action = "new" }
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, agent_hub_namespace, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubTitle", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubHint", 1, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubSection", 3, 0, -1)

  for line, entry in pairs(agent_hub.line_entries) do
    local row = line - 1
    if entry.action == "new" then
      vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubAction", row, 0, -1)
    elseif entry.action == "project" then
      vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubSection", row, 0, -1)
    elseif entry.name == agent_hub.active then
      vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubActive", row, 0, -1)
    elseif agent_status(entry.name) == "detenido" or (entry.external and not state[entry.name]) then
      vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubStopped", row, 0, -1)
    else
      vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubRunning", row, 0, -1)
    end
  end
  local section_row = #lines - #AGENTS - 1
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubSection", section_row, 0, -1)
end

local function activate_hub_agent(name, cmd, cwd, external)
  local hub_win = agent_hub.agent_win
  if not (hub_win and vim.api.nvim_win_is_valid(hub_win)) then
    return
  end

  local previous = agent_hub.active and state[agent_hub.active]
  if previous and previous.win == hub_win then
    previous.win = nil
  end

  if not state[name] then
    toggle_tool(name, cmd, cwd)
    if external and state[name] then state[name].external = true end
  end
  local s = state[name]
  if not s or not valid_buf(s.buf) then
    return
  end
  if s.win and vim.api.nvim_win_is_valid(s.win) and s.win ~= hub_win then
    vim.api.nvim_win_close(s.win, true)
  end

  vim.api.nvim_win_set_buf(hub_win, s.buf)
  s.win = hub_win
  agent_hub.active = name
  require("config.agent_usage").activate_quota_monitor(name)
  if s.cwd then
    add_git_root(s.cwd)
    refresh_hub_command_bar()
    refresh_changes_panel(agent_hub.changes_buf, s.cwd)
  end
  render_agent_hub()
  vim.api.nvim_set_current_win(hub_win)
  vim.cmd("startinsert")
  publish_status()
end

local function show_agent_in_hub(name, cmd, cwd)
  if not (agent_hub.tabpage and vim.api.nvim_tabpage_is_valid(agent_hub.tabpage)
      and agent_hub.agent_win and vim.api.nvim_win_is_valid(agent_hub.agent_win)) then
    return false
  end
  vim.api.nvim_set_current_tabpage(agent_hub.tabpage)
  activate_hub_agent(name, cmd, cwd)
  return true
end

local function selected_hub_entry()
  return agent_hub.line_entries and (agent_hub.line_entries[vim.fn.line(".")] or agent_hub.selection)
end

local function rename_hub_session()
  local entry = selected_hub_entry()
  if not entry or entry.action ~= "agent" or not state[entry.name] then
    vim.notify("Selecciona una sesión activa para renombrarla", vim.log.levels.INFO)
    return
  end
  local previous_name = entry.name
  vim.ui.input({ prompt = "Renombrar sesión: ", default = previous_name }, function(new_name)
    new_name = new_name and vim.trim(new_name) or ""
    if new_name == "" or new_name == previous_name then return end
    if state[new_name] then
      vim.notify("Ya existe una sesión llamada " .. new_name, vim.log.levels.WARN)
      return
    end
    local session = state[previous_name]
    if not session then return end
    state[previous_name] = nil
    state[new_name] = session
    if agent_hub.active == previous_name then
      agent_hub.active = new_name
      if agent_hub.agent_win and vim.api.nvim_win_is_valid(agent_hub.agent_win) then
        style_agent_hub_window(agent_hub.agent_win, new_name:upper(), false)
      end
    end
    agent_hub.selection = { name = new_name, cmd = session.cmd, action = "agent" }
    render_agent_hub()
  end)
end

local WELCOME_LINES = {
  "",
  "█████╗  ██████╗ ███████╗███╗   ██╗████████╗",
  "██╔══██╗██╔════╝ ██╔════╝████╗  ██║╚══██╔══╝",
  "███████║██║  ███╗█████╗  ██╔██╗ ██║   ██║   ",
  "██╔══██║██║   ██║██╔══╝  ██║╚██╗██║   ██║   ",
  "██║  ██║╚██████╔╝███████╗██║ ╚████║   ██║   ",
  "╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═══╝   ╚═╝   ",
  "",
  "██╗  ██╗██╗   ██╗██████╗ ",
  "██║  ██║██║   ██║██╔══██╗",
  "███████║██║   ██║██████╔╝",
  "██╔══██║██║   ██║██╔══██╗",
  "██║  ██║╚██████╔╝██████╔╝",
  "╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ",
  "",
  "Elige una sesión en el panel izquierdo para comenzar.",
  "",
  "⏎  abrir agente                    n  nueva instancia",
  "",
  "La terminal no se inicia hasta que tú la selecciones.",
}

local function render_agent_hub_welcome(buf, width)
  local height = vim.o.lines
  if valid_buf(agent_hub.welcome_buf)
      and agent_hub.agent_win and vim.api.nvim_win_is_valid(agent_hub.agent_win) then
    height = vim.api.nvim_win_get_height(agent_hub.agent_win)
  end
  local top_padding = math.max(0, math.floor((height - #WELCOME_LINES) / 2))
  local lines = vim.tbl_map(function(line)
    local padding = math.max(0, math.floor((width - vim.fn.strdisplaywidth(line)) / 2))
    return string.rep(" ", padding) .. line
  end, WELCOME_LINES)
  for _ = 1, top_padding do
    table.insert(lines, 1, "")
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, agent_hub_namespace, 0, -1)
  for row = 1 + top_padding, 13 + top_padding do
    vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubTitle", row, 0, -1)
  end
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubHint", 15 + top_padding, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubAction", 17 + top_padding, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubHint", 19 + top_padding, 0, -1)
end

create_agent_hub_welcome = function(width)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  render_agent_hub_welcome(buf, width)
  return buf
end

local function create_agent_hub_command_bar()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  local path = vim.fn.fnamemodify(vim.fn.getcwd(), ":~")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "  " .. path .. " · Agent Hub",
    "  [ ↵ Abrir ] [ n Nueva ] [ u Cuota ] [ i Renombrar ] [ ! Detener ] [ d Diff ] [ g Repos ] [ c Commit ] [ a Copilot ] [ m Expandir ]",
  })
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubTitle", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubAction", 1, 0, -1)
  return buf
end

refresh_hub_command_bar = function()
  local buf = agent_hub.command_buf
  if not valid_buf(buf) then return end
  local path = vim.fn.fnamemodify(agent_hub.git_root or vim.fn.getcwd(), ":~")
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "  " .. path .. " · Agent Hub" })
  vim.bo[buf].modifiable = false
end

local function resize_hub_window(direction)
  if direction == "left" then
    vim.cmd("vertical resize +5")
  elseif direction == "right" then
    vim.cmd("vertical resize -5")
  elseif direction == "up" then
    vim.cmd("resize +2")
  elseif direction == "down" then
    vim.cmd("resize -2")
  end
end

local function move_hub_window(direction)
  local targets = { left = "h", right = "l", up = "k", down = "j" }
  local target = targets[direction]
  if target then
    vim.cmd("wincmd " .. target)
  end
end

local function arm_hub_resize(buf)
  if not valid_buf(buf) then return end

  local directions = {
    ["<Left>"] = "left",
    ["<Right>"] = "right",
    ["<Up>"] = "up",
    ["<Down>"] = "down",
    ["<C-Left>"] = "left",
    ["<C-Right>"] = "right",
    ["<C-Up>"] = "up",
    ["<C-Down>"] = "down",
  }
  local token = (vim.b[buf].agent_hub_resize_token or 0) + 1
  vim.b[buf].agent_hub_resize_token = token
  vim.b[buf].agent_hub_resize_pending = true

  local function clear_resize_maps()
    if not valid_buf(buf) then return end
    vim.b[buf].agent_hub_resize_pending = false
    for key in pairs(directions) do
      pcall(vim.keymap.del, { "n", "t" }, key, { buffer = buf })
    end
    map_hub_navigation(buf)
  end

  for key, direction in pairs(directions) do
    vim.keymap.set({ "n", "t" }, key, function()
      if not vim.b[buf].agent_hub_resize_pending then return end
      resize_hub_window(direction)
      local next_token = (vim.b[buf].agent_hub_resize_token or 0) + 1
      vim.b[buf].agent_hub_resize_token = next_token
      vim.defer_fn(function()
    if valid_buf(buf) and vim.b[buf].agent_hub_resize_token == next_token then
          clear_resize_maps()
        end
      end, 1000)
    end, { buffer = buf, nowait = true, desc = "Aplicar redimensionado " .. direction })
  end

  vim.defer_fn(function()
    if valid_buf(buf) and vim.b[buf].agent_hub_resize_token == token then
      clear_resize_maps()
    end
  end, 2000)
end

map_hub_navigation = function(buf)
  if not valid_buf(buf) then return end
  local directions = {
    ["<C-Left>"] = "left",
    ["<C-Right>"] = "right",
    ["<C-Up>"] = "up",
    ["<C-Down>"] = "down",
  }
  for key, direction in pairs(directions) do
    vim.keymap.set({ "n", "t" }, key, function()
      move_hub_window(direction)
    end, { buffer = buf, desc = "Ir al panel " .. direction })
  end

  vim.keymap.set({ "n", "t" }, "<C-A>", function()
    arm_hub_resize(buf)
  end, { buffer = buf, desc = "Preparar redimensionado del Hub" })
end

local function toggle_hub_bottom_terminal()
  local win = agent_hub.command_win
  if not (win and vim.api.nvim_win_is_valid(win)) then return end
  if valid_buf(agent_hub.console_buf)
      and vim.api.nvim_win_get_buf(win) == agent_hub.console_buf then
    vim.api.nvim_win_set_buf(win, agent_hub.command_buf)
    style_agent_hub_window(win, "ACCIONES", false)
    return
  end
  if not valid_buf(agent_hub.console_buf) then
    local cwd = (state[agent_hub.active] or {}).cwd or agent_hub.git_root or vim.fn.getcwd()
    agent_hub.console_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[agent_hub.console_buf].bufhidden = "hide"
    vim.api.nvim_win_set_buf(win, agent_hub.console_buf)
    map_hub_navigation(agent_hub.console_buf)
    vim.fn.termopen(vim.o.shell, { cwd = cwd })
    vim.keymap.set("n", "t", toggle_hub_bottom_terminal,
      { buffer = agent_hub.console_buf, desc = "Volver a acciones" })
  else
    vim.api.nvim_win_set_buf(win, agent_hub.console_buf)
  end
  style_agent_hub_window(win, "TERMINAL  ·  auxiliar", false)
  vim.api.nvim_set_current_win(win)
  vim.cmd("startinsert")
end

refresh_hub_changes = function()
  local buf = agent_hub.changes_buf
  if type(buf) ~= "number" or not vim.api.nvim_buf_is_valid(buf) then
    vim.notify("El panel de cambios ya no está disponible. Abre de nuevo AgentHub.", vim.log.levels.WARN)
    return
  end
  refresh_changes_panel(buf, agent_hub.git_root)
  vim.api.nvim_buf_clear_namespace(buf, agent_hub_namespace, 0, -1)
  for row = 2, 3 do
    vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubAction", row, 0, -1)
  end
end

local function choose_hub_git_folder()
  local folder = vim.fn.input({
    prompt = "Carpeta Git (Tab completa carpetas): ",
    default = agent_hub.git_root,
    completion = "dir",
  })
  if folder == "" then return end
  folder = vim.fn.fnamemodify(vim.fn.expand(folder), ":p")
  local root = git_output(folder, { "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 then
    vim.notify("La carpeta elegida no contiene un repositorio Git", vim.log.levels.WARN)
    return
  end
  add_git_root(root[1])
  refresh_hub_command_bar()
  refresh_hub_changes()
end

open_hub_repo_menu = function()
  local win = agent_hub.changes_win
  if not (win and vim.api.nvim_win_is_valid(win)) then return end
  local previous = vim.api.nvim_win_get_buf(win)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "agent-repositories"
  vim.api.nvim_buf_set_name(buf, "Git Hub Repositories")
  local lines = {
    " GIT HUB  ·  REPOSITORIOS ACTIVOS",
    "",
    " Selecciona un repositorio:",
    "",
  }
  for index, root in ipairs(agent_hub.git_roots or {}) do
    local marker = root == agent_hub.git_root and "●" or "○"
    lines[#lines + 1] = string.format(" %d  %s  %s", index, marker, vim.fn.fnamemodify(root, ":~"))
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = " a  agregar repositorio"
  lines[#lines + 1] = " q  volver a cambios"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_win_set_buf(win, buf)
  vim.b[buf].git_hub_repo_lines = agent_hub.git_roots or {}

  local function restore()
    if vim.api.nvim_win_is_valid(win) and valid_buf(previous) then
      vim.api.nvim_win_set_buf(win, previous)
      style_agent_hub_window(win, "CAMBIOS  ·  Git", false)
      refresh_hub_changes()
    end
  end
  vim.keymap.set("n", "q", restore, { buffer = buf, desc = "Volver a cambios Git" })
  vim.keymap.set("n", "<Esc>", restore, { buffer = buf, desc = "Volver a cambios Git" })
  vim.keymap.set("n", "a", function()
    choose_hub_git_folder()
    if vim.api.nvim_win_is_valid(win) then open_hub_repo_menu() end
  end, { buffer = buf, desc = "Agregar repositorio Git" })
  vim.keymap.set("n", "<CR>", function()
    local index = vim.fn.line(".") - 4
    local root = (vim.b[buf].git_hub_repo_lines or {})[index]
    if not root then return end
    agent_hub.git_root = root
    restore()
  end, { buffer = buf, desc = "Seleccionar repositorio" })
end

local function search_hub_files()
  local ok, builtin = pcall(require, "telescope.builtin")
  if not ok then
    vim.notify("La búsqueda de archivos necesita telescope.nvim", vim.log.levels.ERROR)
    return
  end
  discard_git_object_buffers()
  builtin.git_files({
    cwd = agent_hub.git_root,
    prompt_title = "Archivos del repositorio",
    show_untracked = true,
    previewer = true,
  })
end

local function return_to_hub_changes()
  if agent_hub.changes_win and vim.api.nvim_win_is_valid(agent_hub.changes_win) then
    if type(agent_hub.changes_buf) ~= "number"
        or not vim.api.nvim_buf_is_valid(agent_hub.changes_buf) then
      return
    end
    vim.api.nvim_win_set_buf(agent_hub.changes_win, agent_hub.changes_buf)
    style_agent_hub_window(agent_hub.changes_win, "CAMBIOS  ·  Git", false)
    refresh_hub_changes()
  end
end

local function open_hub_changed_file()
  local changes_buf = agent_hub.changes_buf
  if type(changes_buf) ~= "number" or not vim.api.nvim_buf_is_valid(changes_buf) then
    vim.notify("El panel de cambios ya no está disponible. Pulsa r para actualizar.", vim.log.levels.WARN)
    return false
  end
  local file_lines = vim.b[changes_buf].agent_hub_changed_files
  if type(file_lines) ~= "table" then return false end
  local entry = file_lines[vim.fn.line(".")]
  if type(entry) ~= "table" or type(entry.root) ~= "string" or type(entry.path) ~= "string" then
    return false
  end
  local lines = git_output(entry.root, { "diff", "--", entry.path })
  if #lines == 0 then
    lines = git_output(entry.root, { "diff", "--cached", "--", entry.path })
  end
  if #lines == 0 then
    lines = { "", " Sin diff disponible: el archivo es nuevo o no está seguido por Git.", "", " q o Esc · volver a cambios" }
  else
    table.insert(lines, 1, " q o Esc · volver a cambios")
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "diff"
  vim.api.nvim_buf_set_name(buf, "Git Diff " .. entry.path)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_win_set_buf(agent_hub.changes_win, buf)
  style_agent_hub_window(agent_hub.changes_win, "DIFF  ·  " .. entry.path, false)
  vim.keymap.set("n", "q", return_to_hub_changes, { buffer = buf, desc = "Volver a cambios Git" })
  vim.keymap.set("n", "<Esc>", return_to_hub_changes, { buffer = buf, desc = "Volver a cambios Git" })
  vim.keymap.set("n", "<leader>gb", return_to_hub_changes,
    { buffer = buf, desc = "Git: volver al árbol de cambios" })
  return true
end

local function commit_hub_changes()
  local changes_buf = agent_hub.changes_buf
  if type(changes_buf) ~= "number" or not vim.api.nvim_buf_is_valid(changes_buf) then
    vim.notify("El panel de cambios ya no está disponible. Pulsa r para actualizar.", vim.log.levels.WARN)
    return
  end
  local file_lines = vim.b[changes_buf].agent_hub_changed_files
  local candidate = type(file_lines) == "table" and file_lines[vim.fn.line(".")] or nil
  local selected = type(candidate) == "table" and candidate or nil
  local root = selected and type(selected.root) == "string" and selected.root
    or (type(agent_hub.git_root) == "string" and agent_hub.git_root or vim.fn.getcwd())
  require("config.git_commit").open(root, function()
    if not is_shutting_down then return_to_hub_changes() end
  end)
end

local function restore_hub_layout()
  if agent_hub.maximized then
    vim.cmd("wincmd =")
    agent_hub.maximized = false
    if layout_agent_hub then layout_agent_hub() end
    return true
  end
  return false
end

local function toggle_hub_maximize()
  if not restore_hub_layout() then
    vim.cmd("wincmd |")
    vim.cmd("wincmd _")
    agent_hub.maximized = true
  end
end

layout_agent_hub = function()
  if agent_hub.maximized then return end
  local sidebar = agent_hub.sidebar_win
  local changes = agent_hub.changes_win
  local command = agent_hub.command_win
  if not (sidebar and changes and command) then return end
  if not (vim.api.nvim_win_is_valid(sidebar)
      and vim.api.nvim_win_is_valid(changes)
      and vim.api.nvim_win_is_valid(command)) then
    return
  end

  local columns = vim.o.columns
  local sidebar_width = math.min(36, math.max(28, math.floor(columns * 0.20)))
  local changes_width = math.min(42, math.max(30, math.floor(columns * 0.24)))
  pcall(vim.api.nvim_win_set_width, sidebar, sidebar_width)
  pcall(vim.api.nvim_win_set_width, changes, changes_width)
  pcall(vim.api.nvim_win_set_height, command, 2)
end

open_agent_hub = function()
  discard_git_object_buffers()
  local hub_tabpage = agent_hub.tabpage
  if not (hub_tabpage and vim.api.nvim_tabpage_is_valid(hub_tabpage)) then
    for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
      local ok, is_agent_hub = pcall(vim.api.nvim_tabpage_get_var, tabpage, "agent_hub")
      if ok and is_agent_hub then
        hub_tabpage = tabpage
        break
      end
    end
  end
  if hub_tabpage and vim.api.nvim_tabpage_is_valid(hub_tabpage) then
    vim.api.nvim_set_current_tabpage(hub_tabpage)
    if agent_hub.sidebar_win and vim.api.nvim_win_is_valid(agent_hub.sidebar_win) then
      vim.api.nvim_set_current_win(agent_hub.sidebar_win)
    end
    return
  end

  vim.cmd("tabnew")
  local tabpage = vim.api.nvim_get_current_tabpage()
  vim.api.nvim_tabpage_set_var(tabpage, "agent_hub", true)
  local projects_ok, projects = pcall(require, "config.projects")
  if projects_ok then
    projects.refresh_tabs()
  end
  local agent_placeholder = vim.api.nvim_get_current_buf()
  local agent_win = vim.api.nvim_get_current_win()
  vim.cmd("rightbelow vsplit")
  local changes_win = vim.api.nvim_get_current_win()
  local changes_buf = create_changes_panel()
  vim.api.nvim_win_set_buf(changes_win, changes_buf)
  vim.cmd("topleft 30vnew")
  local sidebar_win = vim.api.nvim_get_current_win()
  local sidebar_placeholder = vim.api.nvim_get_current_buf()
  local sidebar_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[sidebar_buf].buftype = "nofile"
  vim.bo[sidebar_buf].bufhidden = "wipe"
  vim.bo[sidebar_buf].swapfile = false
  vim.bo[sidebar_buf].filetype = "agent-hub"
  vim.api.nvim_buf_set_name(sidebar_buf, "Agent Hub " .. sidebar_buf)
  vim.api.nvim_win_set_buf(sidebar_win, sidebar_buf)
  vim.cmd("botright 2new")
  local command_win = vim.api.nvim_get_current_win()
  local command_placeholder = vim.api.nvim_get_current_buf()

  setup_agent_hub_highlights()
  local welcome_buf = create_agent_hub_welcome(vim.api.nvim_win_get_width(agent_win))
  local command_buf = create_agent_hub_command_bar()
  vim.api.nvim_win_set_buf(agent_win, welcome_buf)
  vim.api.nvim_win_set_buf(command_win, command_buf)
  for _, placeholder in ipairs({ agent_placeholder, sidebar_placeholder, command_placeholder }) do
    if valid_buf(placeholder)
      and vim.api.nvim_buf_get_name(placeholder) == ""
      and not vim.bo[placeholder].modified
      and #vim.fn.win_findbuf(placeholder) == 0 then
      vim.api.nvim_buf_delete(placeholder, { force = true })
    end
  end
  agent_hub = {
    tabpage = tabpage,
    buf = sidebar_buf,
    sidebar_win = sidebar_win,
    agent_win = agent_win,
    changes_win = changes_win,
    changes_buf = changes_buf,
    command_win = command_win,
    command_buf = command_buf,
    welcome_buf = welcome_buf,
    git_root = vim.fn.getcwd(),
    git_roots = { vim.fn.getcwd() },
    collapsed_directories = {},
  }
  style_agent_hub_window(sidebar_win, "AGENT HUB  ·  sesiones", true)
  style_agent_hub_window(changes_win, "CAMBIOS  ·  Git", false)
  style_agent_hub_window(command_win, "ACCIONES", false)
  style_agent_hub_window(agent_win, "BIENVENIDO", false)
  layout_agent_hub()
  render_agent_hub_welcome(welcome_buf, vim.api.nvim_win_get_width(agent_win))
  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("AgentHubWelcomeCentering", { clear = true }),
    callback = function()
      layout_agent_hub()
      if valid_buf(agent_hub.welcome_buf)
          and agent_hub.agent_win and vim.api.nvim_win_is_valid(agent_hub.agent_win) then
        render_agent_hub_welcome(agent_hub.welcome_buf, vim.api.nvim_win_get_width(agent_hub.agent_win))
      end
    end,
  })
  refresh_hub_changes()

  local function open_selected_project()
    local entry = selected_hub_entry()
    if entry and entry.action == "project" then
      require("config.projects").open(entry.cwd)
    end
  end

  local function open_selected_agent()
    local entry = selected_hub_entry()
    if not entry then return end
    if entry.action == "project" then
      open_selected_project()
    elseif entry.action == "new" then
      start_new_instance(entry.name, entry.cmd)
    else
      activate_hub_agent(entry.name, entry.cmd, entry.cwd, entry.external)
      style_agent_hub_window(agent_win, entry.name:upper(), false)
    end
  end

  local function stop_selected_agent()
    local entry = selected_hub_entry()
    if not entry or entry.action ~= "agent" or not state[entry.name] then return end
    local s = state[entry.name]
    if s.win == agent_hub.agent_win then
      s.win = nil
      vim.api.nvim_win_set_buf(agent_hub.agent_win, hub_welcome_buffer())
      agent_hub.active = nil
      style_agent_hub_window(agent_hub.agent_win, "BIENVENIDO", false)
    end
    stop_agent(entry.name)
    render_agent_hub()
  end

  local function create_new_agent_instance()
    vim.ui.select(AGENTS, {
      prompt = "Nueva instancia de:",
      format_item = function(agent) return agent.name end,
    }, function(agent)
      if agent then start_new_instance(agent.name, agent.cmd) end
    end)
  end

  local function run_changes_button()
    local row = vim.fn.line(".")
    if row == 3 then
      open_hub_repo_menu()
    elseif row == 4 then
      refresh_hub_changes()
    elseif row == 5 then
      search_hub_files()
    elseif row == 6 then
      commit_hub_changes()
    else
      return false
    end
    return true
  end

  local function update_hub_hover(line)
    local entry = agent_hub.line_entries and agent_hub.line_entries[line]
    if entry then
      agent_hub.selection = entry
      show_hub_hover(entry)
    else
      close_hub_hover()
    end
  end

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = sidebar_buf,
    callback = function()
      update_hub_hover(vim.fn.line("."))
    end,
  })
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = sidebar_buf,
    callback = close_hub_hover,
  })

  vim.keymap.set("n", "<CR>", function()
    open_selected_agent()
  end, { buffer = sidebar_buf, desc = "Abrir agente seleccionado" })
  vim.keymap.set("n", "n", function()
    create_new_agent_instance()
  end, { buffer = sidebar_buf, desc = "Crear instancia de agente" })
  vim.keymap.set("n", "!", function()
    stop_selected_agent()
  end, { buffer = sidebar_buf, desc = "Detener agente seleccionado" })
  vim.keymap.set("n", "i", rename_hub_session, { buffer = sidebar_buf, desc = "Renombrar sesión seleccionada" })
  vim.keymap.set("n", "d", function()
    local entry = selected_hub_entry()
    if entry and entry.action == "agent" then show_agent_diff(entry.name) end
  end, { buffer = sidebar_buf, desc = "Ver cambios del agente" })
  vim.keymap.set("n", "r", function()
    refresh_hub_changes()
    render_agent_hub()
  end, { buffer = sidebar_buf, desc = "Actualizar paneles" })
  vim.keymap.set("n", "p", function()
    open_selected_project()
  end, { buffer = sidebar_buf, desc = "Abrir ruta del proyecto seleccionado" })
  vim.keymap.set("n", "t", function()
    if agent_hub.active and vim.api.nvim_win_is_valid(agent_win) then
      vim.api.nvim_set_current_win(agent_win)
      vim.cmd("startinsert")
    end
  end, { buffer = sidebar_buf, desc = "Ir a terminal activa" })
  vim.keymap.set("n", "g", open_hub_repo_menu, { buffer = sidebar_buf, desc = "Seleccionar repositorio Git" })
  vim.keymap.set("n", "a", authenticate_copilot, { buffer = sidebar_buf, desc = "Autenticar GitHub Copilot" })
  vim.keymap.set("n", "m", toggle_hub_maximize, { buffer = sidebar_buf, desc = "Maximizar/restaurar panel" })

  for _, buf in ipairs({ changes_buf, command_buf }) do
    vim.keymap.set("n", "<CR>", open_selected_agent, { buffer = buf, desc = "Abrir agente seleccionado" })
    vim.keymap.set("n", "n", create_new_agent_instance, { buffer = buf, desc = "Crear nueva instancia" })
    vim.keymap.set("n", "!", stop_selected_agent, { buffer = buf, desc = "Detener agente seleccionado" })
    vim.keymap.set("n", "i", rename_hub_session, { buffer = buf, desc = "Renombrar sesión seleccionada" })
    vim.keymap.set("n", "d", function()
      local entry = selected_hub_entry()
      if entry and entry.action == "agent" then show_agent_diff(entry.name) end
    end, { buffer = buf, desc = "Ver diff del agente seleccionado" })
    vim.keymap.set("n", "g", open_hub_repo_menu, { buffer = buf, desc = "Seleccionar repositorio Git" })
    vim.keymap.set("n", "c", commit_hub_changes, { buffer = buf, desc = "Crear commit con Copilot" })
    vim.keymap.set("n", "a", authenticate_copilot, { buffer = buf, desc = "Autenticar GitHub Copilot" })
    vim.keymap.set("n", "r", refresh_hub_changes, { buffer = buf, desc = "Actualizar cambios" })
    vim.keymap.set("n", "m", toggle_hub_maximize, { buffer = buf, desc = "Maximizar/restaurar panel" })
  end
  vim.keymap.set("n", "t", toggle_hub_bottom_terminal, { buffer = command_buf, desc = "Terminal auxiliar" })
  vim.keymap.set("n", "<C-p>", search_hub_files, { buffer = changes_buf, desc = "Buscar archivos del repositorio Git" })
  vim.keymap.set("n", "<CR>", function()
    if not toggle_changes_folder(changes_buf) and not run_changes_button() and not open_hub_changed_file() then open_selected_agent() end
  end, { buffer = changes_buf, desc = "Ejecutar botón de cambios" })
  vim.keymap.set("n", "<LeftMouse>", function()
    if not toggle_changes_folder(changes_buf) and not run_changes_button() then open_hub_changed_file() end
  end, { buffer = changes_buf, desc = "Pulsar botón de cambios" })
  for _, buf in ipairs({ sidebar_buf, changes_buf, command_buf, welcome_buf }) do
    map_hub_navigation(buf)
    vim.keymap.set("n", "q", close_agent_hub, { buffer = buf, desc = "Cerrar AgentHub" })
    vim.keymap.set("n", "<Esc>", restore_hub_layout, { buffer = buf, desc = "Restaurar tamaño del Hub" })
    vim.keymap.set("n", "<C-Left>", function() move_hub_window("left") end,
      { buffer = buf, desc = "Ir al panel izquierdo" })
    vim.keymap.set("n", "<C-Right>", function() move_hub_window("right") end,
      { buffer = buf, desc = "Ir al panel derecho" })
    vim.keymap.set("n", "<C-Up>", function() move_hub_window("up") end,
      { buffer = buf, desc = "Ir al panel superior" })
    vim.keymap.set("n", "<C-Down>", function() move_hub_window("down") end,
      { buffer = buf, desc = "Ir al panel inferior" })
  end

  render_agent_hub()
  vim.api.nvim_set_current_win(sidebar_win)
end

close_agent_hub = function()
  local tabpage = agent_hub.tabpage
  if not (tabpage and vim.api.nvim_tabpage_is_valid(tabpage)) then
    for _, candidate in ipairs(vim.api.nvim_list_tabpages()) do
      local ok, is_agent_hub = pcall(vim.api.nvim_tabpage_get_var, candidate, "agent_hub")
      if ok and is_agent_hub then
        tabpage = candidate
        break
      end
    end
  end
  if not (tabpage and vim.api.nvim_tabpage_is_valid(tabpage)) then return end
  close_hub_hover()
  local hub_wins = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do hub_wins[win] = true end
  vim.api.nvim_set_current_tabpage(tabpage)
  vim.cmd("tabclose!")
  for _, session in pairs(state) do
    if session.win and hub_wins[session.win] then session.win = nil end
  end
  agent_hub = {}
  publish_status()
end

toggle_tool = function(name, cmd, cwd)
  local s = state[name]

  if session_is_visible(s) then
    if agent_hub.active == name and s.win == agent_hub.agent_win then
      vim.api.nvim_win_set_buf(s.win, hub_welcome_buffer())
      s.win = nil
      agent_hub.active = nil
      style_agent_hub_window(agent_hub.agent_win, "BIENVENIDO", false)
      render_agent_hub()
      publish_status()
      return
    end
    -- force=true: los buffers de terminal quedan "modificados" (hay
    -- contenido sin guardar) apenas el proceso escribe algo, así que sin
    -- forzar Vim bloquea el cierre con E37/E162 -- no hay nada que
    -- "guardar" en una terminal, así que forzar acá es seguro.
    vim.api.nvim_win_close(s.win, true)
    s.win = nil
    close_changes_panel(s)
    publish_status()
    return
  end

  if s and s.win and vim.api.nvim_win_is_valid(s.win) then
    s.win = nil
  end

  if s and valid_buf(s.buf) then
    s.win = vim.api.nvim_open_win(s.buf, true, float_opts(name))
    map_hub_navigation(s.buf)
    vim.cmd("startinsert")
    publish_status()
    return
  end

  cwd = cwd or choose_session_directory()
  if not cwd then return end

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, float_opts(name))
  map_hub_navigation(buf)
  vim.fn.termopen(cmd, {
    cwd = cwd,
    on_exit = function()
      if is_shutting_down then return end
      vim.schedule(function()
        if is_shutting_down then return end
        if agent_hub.active == name and agent_hub.agent_win and vim.api.nvim_win_is_valid(agent_hub.agent_win) then
          vim.api.nvim_win_set_buf(agent_hub.agent_win, hub_welcome_buffer())
          agent_hub.active = nil
          style_agent_hub_window(agent_hub.agent_win, "BIENVENIDO", false)
        end
        state[name] = nil
        render_agent_hub()
        publish_status()
      end)
    end,
  })
  -- "q"/"d" sueltas: normal-mode SOLO a propósito -- el flotante abre en
  -- modo terminal (insert) para poder tipear en el CLI, y ahí una letra
  -- suelta interceptada te impediría escribir esa letra en tus prompts.
  -- Para no obligar a salir del modo terminal (<C-\><C-n>) antes, los
  -- mismos tres se repiten con Alt en AMBOS modos: Alt no lo usa ningún
  -- CLI de estos para texto, así que es seguro interceptarlo siempre.
  vim.keymap.set("n", "q", function()
    toggle_tool(name, cmd)
  end, { buffer = buf, desc = "Ocultar " .. name })
  vim.keymap.set("n", "d", function()
    show_agent_diff(name)
  end, { buffer = buf, desc = "Ver cambios de " .. name .. " (Diffview)" })
  vim.keymap.set({ "n", "t" }, "<A-q>", function()
    toggle_tool(name, cmd)
  end, { buffer = buf, desc = "Ocultar " .. name })
  vim.keymap.set({ "n", "t" }, "<A-d>", function()
    show_agent_diff(name)
  end, { buffer = buf, desc = "Ver cambios de " .. name .. " (Diffview)" })
  vim.keymap.set({ "n", "t" }, "<A-k>", function()
    stop_agent(name)
  end, { buffer = buf, desc = "Matar " .. name })
  -- Alt-a = selector rápido de sesiones desde afuera, pero alcanzable
  -- sin salir del agente en el que estás parado.
  vim.keymap.set({ "n", "t" }, "<A-a>", function()
    open_agents_picker()
  end, { buffer = buf, desc = "Modo agentes (picker)" })
  state[name] = { buf = buf, win = win, cmd = cmd, cwd = cwd, dirty_before = dirty_files_set() or {} }
  vim.api.nvim_create_autocmd("WinClosed", {
    callback = function()
      if is_shutting_down then return end
      vim.schedule(function()
        if is_shutting_down then return end
        local session = state[name]
        if not session or session_is_visible(session) then return end
        if agent_hub.active == name then
          agent_hub.active = nil
          if agent_hub.agent_win and vim.api.nvim_win_is_valid(agent_hub.agent_win) then
            vim.api.nvim_win_set_buf(agent_hub.agent_win, hub_welcome_buffer())
            style_agent_hub_window(agent_hub.agent_win, "BIENVENIDO", false)
          end
        end
        render_agent_hub()
        publish_status()
      end)
    end,
  })
  vim.cmd("startinsert")
  publish_status()
end

-- Para el picker: si ya está visible, solo enfoca (no la oculta, a
-- diferencia de toggle_tool que es on/off para el atajo directo).
local function focus_or_start(name, cmd)
  local s = state[name]
  if session_is_visible(s) then
    vim.api.nvim_set_current_win(s.win)
    vim.cmd("startinsert")
    return
  end
  toggle_tool(name, cmd)
end

-- Nueva instancia con nombre propio (ej. "Claude: bug login") en vez del
-- auto "#2"/"#3" -- se ofrece como default por si no querés pensar uno.
start_new_instance = function(base, cmd)
  vim.ui.input({ prompt = "Nombre para la nueva instancia de " .. base .. ": ", default = next_instance_name(base) }, function(input)
    if input and input ~= "" then
      if not show_agent_in_hub(input, cmd) then
        focus_or_start(input, cmd)
      end
    end
  end)
end

agent_status = function(name)
  local s = state[name]
  if not s then
    return "detenido"
  end
  if session_is_visible(s) then
    return "visible"
  end
  return "oculto"
end

stop_agent = function(name)
  local s = state[name]
  if not s then
    return
  end
  if valid_buf(s.buf) then
    local job = vim.b[s.buf].terminal_job_id
    if job then
      vim.fn.jobstop(job)
    end
  end
  if is_shutting_down then
    state[name] = nil
    return
  end
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_close(s.win, true)
  end
  local buf = s.buf
  if valid_buf(buf) and #vim.fn.win_findbuf(buf) == 0 then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  close_changes_panel(s)
  state[name] = nil
  publish_status()
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("AgentHubCleanup", { clear = true }),
  callback = function()
    is_shutting_down = true
    local names = {}
    for name in pairs(state) do
      names[#names + 1] = name
    end
    for _, name in ipairs(names) do
      stop_agent(name)
    end
  end,
})

STATUS_ICON = { visible = "●", oculto = "○", disponible = "◇", detenido = "◌" }

-- Agentes base + cualquier instancia extra ya corriendo ("Claude Code #2")
-- + una opción "+ nueva instancia" por cada herramienta.
local function build_picker_entries()
  local entries = {}
  local seen = {}

  for _, agent in ipairs(AGENTS) do
    table.insert(entries, { name = agent.name, cmd = agent.cmd, action = "toggle" })
    seen[agent.name] = true
  end

  for name in pairs(state) do
    if not seen[name] then
      local base = name:match("^(.-) #%d+$")
      local cmd
      for _, agent in ipairs(AGENTS) do
        if agent.name == base then
          cmd = agent.cmd
        end
      end
      table.insert(entries, { name = name, cmd = cmd, action = "toggle" })
    end
  end

  for _, agent in ipairs(AGENTS) do
    table.insert(entries, {
      name = "+ nueva instancia de " .. agent.name,
      cmd = agent.cmd,
      base = agent.name,
      action = "new",
    })
  end

  return entries
end

open_agents_picker = function()
  local ok_telescope = pcall(require, "telescope")
  if not ok_telescope then
    vim.notify("Modo agentes necesita telescope.nvim", vim.log.levels.ERROR)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers.new({}, {
    prompt_title = "Agentes de IA (Enter: ir/arrancar, <C-x>: matar, <C-d>: ver diff)",
    finder = finders.new_table({
      results = build_picker_entries(),
      entry_maker = function(entry)
        local display
        if entry.action == "new" then
          display = "  " .. entry.name
        else
          local status = agent_status(entry.name)
          display = string.format("%s %-18s [%s]", STATUS_ICON[status], entry.name, status)
        end
        return { value = entry, display = display, ordinal = entry.name }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      -- get_selected_entry() da nil si el filtro no matchea nada (ej.
      -- escribiste texto y ninguna fila quedó visible) -- sin este guard,
      -- Enter/<C-x>/<C-d> en ese estado tiraban E5108 al indexar ".value"
      -- de nil.
      actions.select_default:replace(function()
        local selected = action_state.get_selected_entry()
        if not selected then
          return
        end
        local entry = selected.value
        actions.close(prompt_bufnr)
        if entry.action == "new" then
          start_new_instance(entry.base, entry.cmd)
        else
          focus_or_start(entry.name, entry.cmd)
        end
      end)
      map({ "i", "n" }, "<C-x>", function()
        local selected = action_state.get_selected_entry()
        if not selected then
          return
        end
        local entry = selected.value
        if entry.action ~= "new" then
          stop_agent(entry.name)
        end
        actions.close(prompt_bufnr)
        open_agents_picker()
      end)
      map({ "i", "n" }, "<C-d>", function()
        local selected = action_state.get_selected_entry()
        if not selected then
          return
        end
        local entry = selected.value
        if entry.action ~= "new" then
          actions.close(prompt_bufnr)
          show_agent_diff(entry.name)
        end
      end)
      return true
    end,
  }):find()
end

local function active_agent_names()
  local names = {}
  for name, s in pairs(state) do
    if valid_buf(s.buf) then
      table.insert(names, name)
    end
  end
  table.sort(names)
  return names
end

local function agent_name_complete(arg_lead)
  return vim.tbl_filter(function(n)
    return n:lower():find(arg_lead:lower(), 1, true) == 1
  end, active_agent_names())
end

local function workspace_name_complete(arg_lead)
  local names = active_agent_names()
  for _, agent in ipairs(AGENTS) do
    if not vim.tbl_contains(names, agent.name) then
      table.insert(names, agent.name)
    end
  end
  return vim.tbl_filter(function(name)
    return name:lower():find(arg_lead:lower(), 1, true) == 1
  end, names)
end

local function open_agent_workspace_picker(arg)
  if arg and arg ~= "" then
    local s = state[arg]
    if s then
      open_agent_workspace(arg, s.cmd)
      return
    end
    for _, agent in ipairs(AGENTS) do
      if agent.name == arg then
        open_agent_workspace(agent.name, agent.cmd)
        return
      end
    end
    vim.notify("Agente no encontrado: " .. arg, vim.log.levels.WARN)
    return
  end

  local choices = {}
  for _, agent in ipairs(AGENTS) do
    table.insert(choices, { name = agent.name, cmd = (state[agent.name] or {}).cmd or agent.cmd })
  end
  for name, s in pairs(state) do
    if not vim.tbl_contains(vim.tbl_map(function(choice) return choice.name end, choices), name) then
      table.insert(choices, { name = name, cmd = s.cmd })
    end
  end
  vim.ui.select(choices, {
    prompt = "Abrir espacio de trabajo del agente:",
    format_item = function(choice) return choice.name end,
  }, function(choice)
    if choice then
      open_agent_workspace(choice.name, choice.cmd)
    end
  end)
end

-- Resuelve a qué agente aplica :AgentDiff / :AgentKill sin argumento:
-- 1) el nombre pasado explícito, 2) si estás parado en su buffer, ese, 3) si
-- solo hay uno corriendo, ese, 4) si hay varios, te lo pregunta.
local function resolve_agent_name(arg, cb)
  if arg and arg ~= "" then
    cb(arg)
    return
  end

  local current_buf = vim.api.nvim_get_current_buf()
  for name, s in pairs(state) do
    if s.buf == current_buf then
      cb(name)
      return
    end
  end

  local names = active_agent_names()
  if #names == 0 then
    vim.notify("No hay agentes corriendo", vim.log.levels.WARN)
  elseif #names == 1 then
    cb(names[1])
  else
    vim.ui.select(names, { prompt = "¿Qué agente?" }, function(choice)
      if choice then
        cb(choice)
      end
    end)
  end
end

local function tool_command(base, bin)
  return function(cmd_opts)
    local full = vim.trim(bin .. " " .. cmd_opts.args)
    local default_cwd = base == "Copilot" and vim.fn.getcwd() or nil
    if cmd_opts.bang then
      start_new_instance(base, full)
    elseif not show_agent_in_hub(base, full, default_cwd) then
      toggle_tool(base, full, default_cwd)
    end
  end
end

vim.api.nvim_create_user_command("Claude", tool_command("Claude Code", "claude"),
  { nargs = "*", bang = true, desc = "Mostrar/ocultar Claude Code (! = nueva instancia)" })

vim.api.nvim_create_user_command("Codex", tool_command("Codex", "codex"),
  { nargs = "*", bang = true, desc = "Mostrar/ocultar Codex (! = nueva instancia)" })

vim.api.nvim_create_user_command("OpenCode", tool_command("OpenCode", "opencode"),
  { nargs = "*", bang = true, desc = "Mostrar/ocultar OpenCode (! = nueva instancia)" })

vim.api.nvim_create_user_command("Gemini", tool_command("Gemini", "gemini"),
  { nargs = "*", bang = true, desc = "Mostrar/ocultar Gemini (! = nueva instancia)" })

-- "CopilotCli", no "Copilot" -- ese nombre ya lo usa zbirenbaum/copilot.lua
-- (:Copilot auth/status/panel, el de la sugerencia ghost-text) y pisarlo
-- rompería ese comando.
vim.api.nvim_create_user_command("CopilotCli", tool_command("Copilot", "copilot"),
  { nargs = "*", bang = true, desc = "Mostrar/ocultar GitHub Copilot CLI (! = nueva instancia)" })

vim.api.nvim_create_user_command("Agents", open_agent_hub, { desc = "Hub de sesiones, terminal y cambios Git" })

vim.api.nvim_create_user_command("AgentWorkspace", function(cmd_opts)
  open_agent_workspace_picker(cmd_opts.args)
end, {
  nargs = "?",
  complete = workspace_name_complete,
  desc = "Agente y cambios Git en dos columnas a pantalla completa",
})

vim.api.nvim_create_user_command("AgentDiff", function(cmd_opts)
  resolve_agent_name(cmd_opts.args, show_agent_diff)
end, {
  nargs = "?",
  complete = agent_name_complete,
  desc = "Ver diff (Diffview) de un agente -- sin argumento: el de tu buffer actual, o te pregunta",
})

vim.api.nvim_create_user_command("AgentKill", function(cmd_opts)
  resolve_agent_name(cmd_opts.args, stop_agent)
end, {
  nargs = "?",
  complete = agent_name_complete,
  desc = "Matar un agente -- sin argumento: el de tu buffer actual, o te pregunta",
})

vim.api.nvim_create_user_command("AgentsKillAll", function()
  local names = active_agent_names()
  if #names == 0 then
    vim.notify("No hay agentes corriendo", vim.log.levels.INFO)
    return
  end
  for _, name in ipairs(names) do
    stop_agent(name)
  end
  vim.notify(("Matados %d agente(s)"):format(#names), vim.log.levels.INFO)
end, { desc = "Matar TODOS los agentes de IA corriendo" })

vim.keymap.set("n", "<leader>aa", open_agent_hub, { desc = "Hub de agentes" })
vim.keymap.set("n", "<leader>aq", close_agent_hub,
  { desc = "Cerrar AgentHub sin detener agentes", nowait = true, silent = true })
vim.api.nvim_create_user_command("AgentHubClose", close_agent_hub,
  { desc = "Cerrar AgentHub sin detener agentes", force = true })

-- Vim exige mayúscula inicial en comandos de usuario (:Claude, no :claude);
-- estas abreviaciones de línea de comandos permiten escribir en minúscula
-- como el binario real, sin duplicar la definición del comando.
vim.cmd("cnoreabbrev claude Claude")
vim.cmd("cnoreabbrev codex Codex")
vim.cmd("cnoreabbrev opencode OpenCode")
vim.cmd("cnoreabbrev gemini Gemini")
vim.cmd("cnoreabbrev copilotcli CopilotCli")
vim.cmd("cnoreabbrev agents Agents")
vim.cmd("cnoreabbrev agentdiff AgentDiff")
vim.cmd("cnoreabbrev agentkill AgentKill")
vim.cmd("cnoreabbrev agentskillall AgentsKillAll")

return {}
