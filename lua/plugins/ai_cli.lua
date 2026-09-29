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
--   :Grok        Mostrar/ocultar Grok CLI
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

local agent_sessions = require("config.agent_sessions")
local i18n = require("config.i18n")
if type(agent_sessions.providers) ~= "function" or type(agent_sessions.remove) ~= "function" then
  package.loaded["config.agent_sessions"] = nil
  agent_sessions = require("config.agent_sessions")
end
-- Solo se ofrecen los agentes cuya CLI está instalada en el sistema.
local AGENTS = vim.tbl_filter(function(agent)
  return agent_sessions.is_installed(agent.cmd)
end, {
  { name = "Claude Code", cmd = "claude" },
  { name = "Codex", cmd = "codex" },
  { name = "OpenCode", cmd = "opencode" },
  { name = "Gemini", cmd = "gemini" },
  { name = "Copilot", cmd = "copilot" },
  { name = "Grok", cmd = "grok" },
})
local project_registry = require("config.projects")
if type(project_registry.toggle_pin) ~= "function" then
  package.loaded["config.projects"] = nil
  project_registry = require("config.projects")
end
local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local GIT_ICON = ""
local spinner_frame = 1
local spinner_timer
local hub_spinner_timer

local state = rawget(_G, "__agent_hub_state") or {} -- name -> { buf, win }
_G.__agent_hub_state = state
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
local restore_hub_layout
local render_project_menu
local render_project_agents
local start_project_spinner
local stop_project_spinner
local start_hub_spinner
local stop_hub_spinner
local show_hub_hover
local close_hub_hover
local command_text
local project_agent_status
local agent_hub_namespace
local agent_hub = {}
local saved_hub_layout = {}
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

-- Nombre vigente de la sesión dueña de `buf`: puede cambiar al renombrarla
-- desde el Hub ("i"), así que los callbacks no deben capturar el nombre.
local function session_name_for_buf(buf, fallback)
  for name, s in pairs(state) do
    if s.buf == buf then return name end
  end
  return fallback
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
      local placeholder = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(placeholder, "Agent Changes Placeholder " .. placeholder)
      vim.api.nvim_win_set_buf(s.changes_win, placeholder)
    end
  end
  s.changes_win = nil
end

local function git_output(root, args)
  local command = { "git", "-C", root or vim.fn.getcwd() }
  vim.list_extend(command, args)
  return vim.fn.systemlist(command)
end

local function is_git_repository(root)
  if type(root) ~= "string" or root == "" then return false end
  git_output(root, { "rev-parse", "--show-toplevel" })
  return vim.v.shell_error == 0
end

local function normalize_project_path(path)
  if type(path) ~= "string" then return "" end
  return vim.fn.fnamemodify(path, ":p"):gsub("/$", "")
end

local function same_project_path(left, right)
  return normalize_project_path(left) == normalize_project_path(right)
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

  local lines = { "", "    ARCHIVOS MODIFICADOS" }
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
          if collapsed == nil then collapsed = true end
          table.insert(lines, string.format(" %s%s %s", prefix, collapsed and "" or "", name))
          folder_lines[#lines] = directory
          if not collapsed then append(child, prefix .. "  ", directory) end
        end
      end
    end
  end
  -- Sangría base para que el contenido quede visualmente dentro de
  -- "ARCHIVOS MODIFICADOS" y del repositorio activo.
  append(root, "    ", "")
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
  roots = vim.tbl_filter(is_git_repository, roots)
  if agent_hub.selected_git_roots then
    roots = vim.tbl_filter(function(repo_root)
      return agent_hub.selected_git_roots[repo_root] == true
    end, roots)
  end
  local active_root = agent_hub.git_root or roots[1]
  local lines = {
    string.format(" GIT HUB  ·  CAMBIOS  ·  %d repositorio(s)", #roots),
    "",
    "  Repo activo: " .. vim.fn.fnamemodify(active_root, ":~"),
  }
  local file_lines = {}
  local folder_lines = {}
  local collapsed = agent_hub.collapsed_directories or {}

  for _, repo_root in ipairs(roots) do
    local project_name = project_registry.name_for(repo_root)
    local project_key = repo_root .. "::__project__"
    local project_collapsed = collapsed[project_key]
    if project_collapsed == nil then project_collapsed = true end
    table.insert(lines, "")
    table.insert(lines, "  " .. (project_collapsed and "▸" or "▾") .. " " .. GIT_ICON .. "  " .. project_name)
    folder_lines[#lines] = { root = repo_root, path = "__project__" }

    local files = git_output(repo_root, { "status", "--short" })
    if vim.v.shell_error ~= 0 then
      table.insert(lines, "    La carpeta no es un repositorio Git")
    else
      files = vim.tbl_filter(function(file) return not is_internal_change(file) end, files)
      if #files == 0 then
        table.insert(lines, "    Sin archivos modificados")
      elseif project_collapsed then
        table.insert(lines, string.format("      %d archivo(s) modificado(s) · plegado", #files))
      else
        local tree_lines, tree_file_lines, tree_folder_lines = changes_tree(files, collapsed, repo_root)
        local tree_offset = #lines
        vim.list_extend(lines, tree_lines)
        for line, path in pairs(tree_file_lines) do
          file_lines[tree_offset + line] = { root = repo_root, path = path }
        end
        for line, path in pairs(tree_folder_lines) do
          folder_lines[tree_offset + line] = { root = repo_root, path = path }
        end
        table.insert(lines, string.format("      %d archivo(s) modificado(s)", #files))
      end
    end
  end
  return lines, file_lines, folder_lines
end

local function refresh_changes_panel(buf, root)
  if type(buf) == "number" and vim.api.nvim_buf_is_valid(buf) then
    local lines, file_lines, folder_lines = changes_panel_lines(root)
    local display_lines = i18n.translate_lines(lines)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)
    vim.bo[buf].modifiable = false
    vim.b[buf].agent_hub_changed_files = file_lines
    vim.b[buf].agent_hub_change_folders = folder_lines
    vim.api.nvim_buf_clear_namespace(buf, agent_hub_namespace, 0, -1)
    for line = 1, #lines do
      local row = line - 1
      if folder_lines[line] then
        local group = folder_lines[line].path == "__project__"
            and "AgentChangesRepo" or "AgentChangesFolder"
        vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, group, row, 0, -1)
      elseif file_lines[line] then
        local text = lines[line]
        local status = text:sub(-2)
        local group = status == "??" and "AgentChangesAdded"
            or status == " D" and "AgentChangesDeleted"
            or status == " M" and "AgentChangesModified"
            or "AgentChangesFile"
        vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, group, row, 0, -1)
      elseif lines[line]:match("archivo%(s%) modificado") then
        vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentChangesSummary", row, 0, -1)
      end
    end
  end
end

local function toggle_changes_folder(buf)
  if type(buf) ~= "number" or not vim.api.nvim_buf_is_valid(buf) then return false end
  local folders = vim.b[buf].agent_hub_change_folders
  if type(folders) ~= "table" then return false end
  local entry = folders[vim.fn.line(".")]
  if not entry then return false end
  agent_hub.collapsed_directories = agent_hub.collapsed_directories or {}
  local root = type(entry) == "table" and entry.root or agent_hub.git_root
  local path = type(entry) == "table" and entry.path or entry
  if type(root) ~= "string" or type(path) ~= "string" then return false end
  local key = root .. "::" .. path
  local collapsed = agent_hub.collapsed_directories[key]
  if collapsed == nil then collapsed = true end
  agent_hub.collapsed_directories[key] = not collapsed
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
  pcall(function() require("config.git_commit").warm() end)
  refresh_changes_panel(buf)
  vim.keymap.set("n", "r", function()
    if refresh_hub_changes then
      refresh_hub_changes()
    else
      refresh_changes_panel(buf, agent_hub.git_root or vim.fn.getcwd())
    end
  end, { buffer = buf, desc = "Actualizar cambios Git" })
  local hover_events = { "CursorMoved" }
  if vim.fn.exists("##MouseMoved") == 1 then
    table.insert(hover_events, "MouseMoved")
  end
  vim.opt.mousemoveevent = true
  vim.api.nvim_create_autocmd(hover_events, {
    buffer = buf,
    callback = function()
      local buffer_vars = vim.b[buf]
      local folders = type(buffer_vars) == "table" and buffer_vars.agent_hub_change_folders
      local entry = type(folders) == "table" and folders[vim.fn.line(".")]
      if type(entry) == "table" and entry.path == "__project__" then
        show_hub_hover({
          action = "project_change",
          display_name = project_registry.name_for(entry.root),
          cwd = entry.root,
        }, vim.api.nvim_get_current_win())
      else
        close_hub_hover()
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    callback = close_hub_hover,
  })
  vim.api.nvim_create_autocmd("WinResized", {
    buffer = buf,
    callback = function()
      local entry = agent_hub.hover_entry
      local target_win = agent_hub.hover_target_win
      if not entry or not target_win or not vim.api.nvim_win_is_valid(target_win) then return end
      close_hub_hover()
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(target_win) then
          show_hub_hover(entry, target_win)
        end
      end)
    end,
  })
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
agent_hub_namespace = vim.api.nvim_create_namespace("agent-hub")

local function setup_agent_hub_highlights()
  local colors = require("config.theme").colors
  vim.api.nvim_set_hl(0, "AgentHubTitle", { fg = colors.green, bold = true })
  vim.api.nvim_set_hl(0, "AgentHubSection", { fg = colors.green_dim, bold = true })
  vim.api.nvim_set_hl(0, "AgentHubHint", { fg = colors.green_dim, italic = true })
  vim.api.nvim_set_hl(0, "AgentHubActive", { bg = colors.selection, fg = colors.green_bright })
  vim.api.nvim_set_hl(0, "AgentHubRunning", { fg = colors.green })
  vim.api.nvim_set_hl(0, "AgentHubStopped", { fg = colors.green_dim })
  vim.api.nvim_set_hl(0, "AgentHubAction", { fg = colors.tan })
  vim.api.nvim_set_hl(0, "AgentChangesRepo", { fg = colors.cyan, bold = true })
  vim.api.nvim_set_hl(0, "AgentChangesFolder", { fg = colors.green, bold = true })
  vim.api.nvim_set_hl(0, "AgentChangesFile", { fg = colors.fg })
  vim.api.nvim_set_hl(0, "AgentChangesModified", { fg = colors.cyan })
  vim.api.nvim_set_hl(0, "AgentChangesAdded", { fg = colors.diff_add_fg })
  vim.api.nvim_set_hl(0, "AgentChangesDeleted", { fg = colors.diff_delete_fg })
  vim.api.nvim_set_hl(0, "AgentChangesSummary", { fg = colors.green_dim, italic = true })
end

local function style_agent_hub_window(win, title, is_sidebar)
  title = i18n.translate_line(title)
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

local function registered_project_entries(active_projects, current_root)
  local entries = {}
  local seen = {}

  local function add(raw_path, display_name, opts)
    if type(raw_path) ~= "string" or raw_path == "" then return end
    local path = normalize_project_path(raw_path)
    if seen[path] then return end
    seen[path] = true
    opts = opts or {}
    local is_active = not active_projects
        or active_projects[path]
        or same_project_path(path, current_root)
    table.insert(entries, {
      name = "Registered project: " .. path,
      display_name = display_name or vim.fn.fnamemodify(path, ":t"),
      cwd = path,
      description = opts.description,
      last = opts.last,
      pinned = opts.pinned == true,
      active = is_active,
      action = "project",
    })
  end

  for _, project in ipairs(project_registry.list()) do
    add(project.path, project.name, project)
  end

  -- Proyectos con sesiones de agentes que aún no se abrieron desde el picker
  -- (por lo que no están en projects.json) también deben listarse acá.
  for _, group in ipairs(agent_sessions.grouped()) do
    add(group.path, group.name, { last = group.updated_at })
  end

  return entries
end

local function registered_project_roots()
  local roots = {}
  for _, entry in ipairs(registered_project_entries()) do
    table.insert(roots, entry.cwd)
  end
  return roots
end

local function external_session_status(session)
  if state[session.name] then return agent_status(session.name) end
  return agent_sessions.status(session)
end

local function active_session_projects()
  local active = {}
  for _, group in ipairs(agent_sessions.grouped()) do
    for _, session in ipairs(group.sessions or {}) do
      if external_session_status(session) == "ejecutando" then
        active[normalize_project_path(group.path)] = true
        break
      end
    end
  end
  for name, session in pairs(state) do
    if session.cwd and agent_status(name) ~= "detenido" then
      active[normalize_project_path(session.cwd)] = true
    end
  end
  return active
end

local function active_agent_entries()
  local entries = {}
  local known = {}

  for name, session in pairs(state) do
    if agent_status(name) ~= "detenido" then
      table.insert(entries, {
        name = name,
        cmd = session.cmd,
        cwd = session.cwd,
        action = "agent",
        external = false,
      })
      known[name] = true
    end
  end

  for _, session in ipairs(agent_sessions.list()) do
    if external_session_status(session) ~= "detenido" and not known[session.name] then
      table.insert(entries, session)
      known[session.name] = true
    end
  end

  table.sort(entries, function(left, right) return left.name < right.name end)
  return entries
end

close_hub_hover = function()
  if agent_hub.hover_win and vim.api.nvim_win_is_valid(agent_hub.hover_win) then
    vim.api.nvim_win_close(agent_hub.hover_win, true)
  end
  agent_hub.hover_win = nil
  agent_hub.hover_buf = nil
  agent_hub.hover_key = nil
  agent_hub.hover_line = nil
  agent_hub.hover_entry = nil
  agent_hub.hover_target_win = nil
end

local function project_change_summary(path)
  if vim.fn.isdirectory(path) ~= 1 then return "carpeta no disponible" end
  local files = git_output(path, { "status", "--short" })
  if vim.v.shell_error ~= 0 then return "no es un repositorio Git" end
  files = vim.tbl_filter(function(file) return not is_internal_change(file) end, files)
  return #files == 0 and "sin cambios" or (#files .. " cambio(s)")
end

local function project_branch(path)
  local branch = git_output(path, { "branch", "--show-current" })[1]
  if branch and vim.trim(branch) ~= "" then return vim.trim(branch) end
  local head = git_output(path, { "rev-parse", "--short", "HEAD" })[1]
  return head and vim.trim(head) ~= "" and "detached@" .. vim.trim(head) or "sin rama"
end

local function project_last_seen(timestamp)
  if type(timestamp) ~= "number" or timestamp <= 0 then return "sin registro" end
  return os.date("%Y-%m-%d %H:%M", timestamp)
end

local function hub_hover_lines(entry)
  if entry.action == "project" then
    local lines = {
      "Proyecto registrado",
      "Nombre: " .. entry.display_name,
      "Ruta: " .. entry.cwd,
      "Rama: " .. project_branch(entry.cwd),
      "Último acceso: " .. project_last_seen(entry.last),
      "Cambios: " .. project_change_summary(entry.cwd),
      "Fijo: " .. (entry.pinned and "sí" or "no"),
      "Estado: " .. (entry.active and "activo" or "inactivo"),
      "Enter  abrir proyecto",
      "p  abrir proyecto",
    }
    if entry.description and entry.description ~= "" then
      table.insert(lines, 4, "Descripción: " .. entry.description)
    end
    return lines
  end
  if entry.action == "project_open" then
    return {
      "Abrir proyecto",
      "Nombre: " .. entry.display_name,
      "Enter  abrir proyecto",
    }
  end
  if entry.action == "project_agents" then
    return {
      "Agentes del proyecto",
      "Nombre: " .. entry.display_name,
      "Enter  listar agentes y estados",
    }
  end
  if entry.action == "project_change" then
    return {
      "Repositorio",
      "Proyecto: " .. entry.display_name,
      "Ruta: " .. entry.cwd,
      "Rama: " .. project_branch(entry.cwd),
      "Cambios: " .. project_change_summary(entry.cwd),
      "Repo activo: " .. vim.fn.fnamemodify(entry.cwd, ":~"),
      "Atajos:",
      "g  repositorios   r  actualizar",
      "c  commit         Ctrl-P  buscar",
      "Enter  plegar/desplegar",
    }
  end
  if entry.action == "noop" then
    return {}
  end
  if entry.action == "agent_command" then
    local agent = entry.agent or entry
    local status = project_agent_status(agent)
    return {
      "Comando del agente",
      "Agente: " .. agent.name,
      "Comando: " .. command_text(agent.cmd),
      "Proyecto: " .. tostring(agent.cwd or "sin ruta"),
      "Estado: " .. status,
    }
  end
  if entry.external then
    local status = external_session_status(entry)
    return {
      "Sesión " .. (entry.kind or "externa"),
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

local function hub_hover_key(entry)
  return table.concat({
    tostring(entry.action or ""),
    tostring(entry.name or ""),
    tostring(entry.cwd or ""),
    tostring(entry.display_name or ""),
    tostring(entry.session_id or ""),
  }, "\0")
end

show_hub_hover = function(entry, target_win)
  target_win = target_win or agent_hub.sidebar_win
  if not entry or entry.action == "new" or not target_win
      or not vim.api.nvim_win_is_valid(target_win) then
    close_hub_hover()
    return
  end

  local line = vim.fn.line(".")
  local key = hub_hover_key(entry)
  if agent_hub.hover_key == key and agent_hub.hover_line == line
      and agent_hub.hover_win and vim.api.nvim_win_is_valid(agent_hub.hover_win) then
    return
  end
  local lines = hub_hover_lines(entry)
  if #lines == 0 then
    close_hub_hover()
    return
  end
  close_hub_hover()
  local width = 44
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line) + 2)
  end
  width = math.min(width, 86)
  local height = #lines
  local target_width = vim.api.nvim_win_get_width(target_win)
  local target_row, target_col = unpack(vim.api.nvim_win_get_position(target_win))
  local hover_gap = 3
  local right_space = vim.o.columns - (target_col + target_width)
  local col
  if right_space >= width + hover_gap then
    col = target_col + target_width + hover_gap
  elseif target_col >= width + hover_gap then
    col = target_col - width - hover_gap
  else
    col = target_col
  end
  local row = math.min(target_row + vim.fn.line(".") - 1, vim.o.lines - height - 2)
  row = math.max(0, row)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_name(buf, "Agent Hub Hover " .. buf)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, i18n.translate_lines(lines))
  vim.bo[buf].modifiable = false
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = row,
    col = col,
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
  agent_hub.hover_key = key
  agent_hub.hover_line = line
  agent_hub.hover_entry = entry
  agent_hub.hover_target_win = target_win
end

local function authenticate_copilot()
  local ok, err = pcall(vim.cmd, "Copilot auth")
  if not ok then
    vim.notify("No se pudo iniciar Copilot: " .. err, vim.log.levels.WARN)
  end
end

local function save_hub_layout()
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
  saved_hub_layout = {
    sidebar_width = vim.api.nvim_win_get_width(sidebar),
    changes_width = vim.api.nvim_win_get_width(changes),
    command_height = vim.api.nvim_win_get_height(command),
  }
end

local function render_agent_hub()
  local buf = agent_hub.buf
  if not valid_buf(buf) then
    return
  end
  stop_project_spinner()
  agent_hub.project_view = nil
  agent_hub.project_group = nil
  if agent_hub.sidebar_win and vim.api.nvim_win_is_valid(agent_hub.sidebar_win) then
    style_agent_hub_window(agent_hub.sidebar_win, "AGENT HUB  ·  sesiones", true)
  end
  if agent_hub.layout_initialized then save_hub_layout() end
  if layout_agent_hub then layout_agent_hub() end

  local lines = {
    "  AGENT HUB",
    "",
  }
  agent_hub.line_entries = {}
  local active_projects = active_session_projects()
  local project_entries = registered_project_entries(active_projects, agent_hub.git_root)
  local project_section_line
  if #project_entries > 0 then
    table.insert(lines, "")
    project_section_line = #lines + 1
    table.insert(lines, "  PROYECTOS REGISTRADOS")
    for _, entry in ipairs(project_entries) do
      local marker = "○"
      table.insert(lines, string.format("  %s  %s", marker, entry.display_name))
      agent_hub.line_entries[#lines] = entry
    end
  end

  table.insert(lines, "")
  table.insert(lines, "  NUEVA INSTANCIA")
  for _, agent in ipairs(AGENTS) do
    table.insert(lines, " + " .. agent.name)
    agent_hub.line_entries[#lines] = { name = agent.name, cmd = agent.cmd, action = "new" }
  end

  lines = i18n.translate_lines(lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, agent_hub_namespace, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubTitle", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubHint", 1, 0, -1)
  if project_section_line then
    vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubSection", project_section_line - 1, 0, -1)
  end

  for line, entry in pairs(agent_hub.line_entries) do
    local row = line - 1
    if entry.action == "new" then
      vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubAction", row, 0, -1)
    elseif entry.action == "project" then
      local group = same_project_path(entry.cwd, agent_hub.git_root)
          and "AgentHubActive" or "AgentHubRunning"
      vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, group, row, 0, -1)
    elseif entry.name == agent_hub.active then
      vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubActive", row, 0, -1)
    elseif (entry.external and external_session_status(entry) == "detenido")
        or (not entry.external and agent_status(entry.name) == "detenido") then
      vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubStopped", row, 0, -1)
    else
      vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubRunning", row, 0, -1)
    end
  end
  if next(active_projects) then
    start_hub_spinner()
  else
    stop_hub_spinner()
  end
end

command_text = function(cmd)
  if type(cmd) == "table" then
    return table.concat(cmd, " ")
  end
  return tostring(cmd or "")
end

local function compact_text(text, width)
  text = tostring(text or "")
  if vim.fn.strdisplaywidth(text) <= width then return text end
  if width <= 3 then return vim.fn.strcharpart(text, 0, width) end
  return vim.fn.strcharpart(text, 0, width - 3) .. "..."
end

local function project_status_icon(status)
  if status == "ejecutando" then
    return SPINNER_FRAMES[spinner_frame]
  end
  if status == "activo" or status == "visible" or status == "oculto" then
    return "●"
  end
  return STATUS_ICON[status] or "◇"
end

local function project_status_label(status)
  if status == "activo" then
    return "listo"
  end
  if status == "visible" or status == "oculto" then
    return "activo"
  end
  return status
end

local function project_agents(group)
  local agents = {}
  local known = {}

  local function add(entry)
    if not entry or not entry.name or known[entry.name] then return end
    known[entry.name] = true
    table.insert(agents, entry)
  end

  for _, session in ipairs(group.sessions or {}) do
    add(session)
  end

  for name, session in pairs(state) do
    if session.cwd and same_project_path(session.cwd, group.path) then
      add({
        name = name,
        cmd = session.cmd,
        cwd = session.cwd,
        action = "agent",
        external = false,
      })
    end
  end

  table.sort(agents, function(left, right) return left.name < right.name end)
  return agents
end

project_agent_status = function(entry)
  if entry.external then return external_session_status(entry) end
  return agent_status(entry.name)
end

local function collect_project_sessions(group)
  if group.sessions_loaded then return end
  local sessions = group.sessions or {}
  local known = {}
  for _, session in ipairs(sessions) do
    known[session.session_id or session.name] = true
  end
  for _, candidate in ipairs(agent_sessions.grouped()) do
    if same_project_path(candidate.path, group.path) then
      for _, session in ipairs(candidate.sessions) do
        local key = session.session_id or session.name
        if not known[key] then
          table.insert(sessions, session)
          known[key] = true
        end
      end
    end
  end
  group.sessions = sessions
  group.sessions_loaded = true
end

local function write_hub_sidebar(lines)
  local buf = agent_hub.buf
  if not valid_buf(buf) then return false end
  lines = i18n.translate_lines(lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, agent_hub_namespace, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubTitle", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubHint", 1, 0, -1)
  if agent_hub.sidebar_win and vim.api.nvim_win_is_valid(agent_hub.sidebar_win) then
    local row = math.min(vim.fn.line("."), #lines)
    vim.api.nvim_win_set_cursor(agent_hub.sidebar_win, { math.max(1, row), 0 })
  end
  return true
end

local function project_active_agents(group)
  local active = {}
  for _, entry in ipairs(project_agents(group)) do
    local status = project_agent_status(entry)
    if status ~= "detenido" then
      table.insert(active, entry)
    end
  end
  return active
end

local function project_has_executing_agent(group)
  for _, entry in ipairs(project_agents(group)) do
    if project_agent_status(entry) == "ejecutando" then return true end
  end
  return false
end

render_project_menu = function(entry, preserve_cursor)
  if not valid_buf(agent_hub.buf) then
    stop_project_spinner()
    stop_hub_spinner()
    return
  end
  stop_hub_spinner()
  local group = entry.group or (entry.path and entry.sessions and entry) or {
    path = entry.cwd,
    name = entry.display_name,
    sessions = {},
  }
  group.path = group.path or entry.cwd
  group.name = group.name or entry.display_name or vim.fn.fnamemodify(group.path or "", ":t")
  group.sessions = group.sessions or {}
  collect_project_sessions(group)
  agent_hub.project_view = "menu"
  agent_hub.project_group = group
  agent_hub.line_entries = {}
  agent_hub.selection = nil
  if agent_hub.sidebar_win and vim.api.nvim_win_is_valid(agent_hub.sidebar_win) then
    style_agent_hub_window(agent_hub.sidebar_win, "PROYECTO  ·  " .. group.name, true)
  end

  local lines = {
    "  PROYECTO",
    "  " .. group.name,
    "",
    "  ACTIVOS",
  }
  local active_entries = project_active_agents(group)
  local width = agent_hub.sidebar_win and vim.api.nvim_win_is_valid(agent_hub.sidebar_win)
      and vim.api.nvim_win_get_width(agent_hub.sidebar_win) or 30
  if #active_entries == 0 then
    table.insert(lines, "  Sin agentes activos")
  else
    for index, active in ipairs(active_entries) do
      if index > 5 then break end
      local status = project_agent_status(active)
      table.insert(lines, string.format("  %s %-18s %s", project_status_icon(status),
        compact_text(active.name, math.max(10, width - 14)), project_status_label(status)))
      agent_hub.line_entries[#lines] = active
    end
  end
  table.insert(lines, "")
  local actions_line = #lines + 1
  table.insert(lines,
    "  ACCIONES")
  local open_entry = {
    name = "Abrir proyecto: " .. group.name,
    display_name = group.name,
    cwd = group.path,
    action = "project_open",
  }
  local agents_entry = {
    name = "Agentes del proyecto: " .. group.name,
    display_name = group.name,
    cwd = group.path,
    group = group,
    action = "project_agents",
  }
  local open_line = #lines + 1
  table.insert(lines, "  ↗ Abrir proyecto")
  local agents_line = #lines + 1
  table.insert(lines, "  ☷ Ver agentes del proyecto")
  table.insert(lines, "")
  table.insert(lines, "  q  volver a proyectos")
  agent_hub.line_entries[open_line] = open_entry
  agent_hub.line_entries[agents_line] = agents_entry
  if not write_hub_sidebar(lines) then
    stop_project_spinner()
    return
  end
  vim.api.nvim_buf_add_highlight(agent_hub.buf, agent_hub_namespace, "AgentHubSection", actions_line - 1, 0, -1)
  for line, action in pairs(agent_hub.line_entries) do
    if action.action == "agent" then
      vim.api.nvim_buf_add_highlight(agent_hub.buf, agent_hub_namespace, "AgentHubRunning", line - 1, 0, -1)
    elseif action.action ~= "noop" then
      vim.api.nvim_buf_add_highlight(agent_hub.buf, agent_hub_namespace, "AgentHubAction", line - 1, 0, -1)
    end
  end
  if agent_hub.sidebar_win and vim.api.nvim_win_is_valid(agent_hub.sidebar_win) then
    local cursor_line = preserve_cursor and vim.fn.line(".") or open_line
    vim.api.nvim_win_set_cursor(agent_hub.sidebar_win, { math.min(cursor_line, #lines), 0 })
  end
  if project_has_executing_agent(group) then
    start_project_spinner()
  else
    stop_project_spinner()
  end
end

render_project_agents = function(group)
  if not valid_buf(agent_hub.buf) then
    stop_project_spinner()
    stop_hub_spinner()
    return
  end
  stop_hub_spinner()
  agent_hub.project_view = "agents"
  agent_hub.project_group = group
  agent_hub.line_entries = {}
  agent_hub.selection = nil
  if agent_hub.sidebar_win and vim.api.nvim_win_is_valid(agent_hub.sidebar_win) then
    style_agent_hub_window(agent_hub.sidebar_win, "AGENTES  ·  " .. group.name, true)
  end

  local lines = {
    "  AGENTES DEL PROYECTO",
    "  " .. group.name,
    "  q  volver al proyecto",
    "",
  }
  local width = agent_hub.sidebar_win and vim.api.nvim_win_is_valid(agent_hub.sidebar_win)
      and vim.api.nvim_win_get_width(agent_hub.sidebar_win) or 30
  local sessions = project_agents(group)
  if #sessions == 0 then
    table.insert(lines, "  Sin agentes registrados en este proyecto")
  end
  local name_width = math.max(10, math.min(18, width - 20))
  local command_width = math.max(10, width - 14)
  local active_sessions = vim.tbl_filter(function(entry)
    return project_agent_status(entry) ~= "detenido"
  end, sessions)
  local stopped_sessions = vim.tbl_filter(function(entry)
    return project_agent_status(entry) == "detenido"
  end, sessions)
  local section_lines = {}

  local function append_session(entry)
    local status = project_agent_status(entry)
    table.insert(lines, string.format("  %s %-" .. name_width .. "s %s", project_status_icon(status),
      compact_text(entry.name, name_width), project_status_label(status)))
    agent_hub.line_entries[#lines] = entry
    table.insert(lines, "      comando: " .. compact_text(command_text(entry.cmd), command_width))
    agent_hub.line_entries[#lines] = { action = "agent_command", agent = entry }
  end

  if #active_sessions > 0 then
    table.insert(lines, "  PERFILES ACTIVOS")
    table.insert(section_lines, #lines)
    for _, entry in ipairs(active_sessions) do append_session(entry) end
  end
  if #stopped_sessions > 0 then
    table.insert(lines, "  AGENTES REGISTRADOS")
    table.insert(section_lines, #lines)
    for _, entry in ipairs(stopped_sessions) do append_session(entry) end
  end
  if not write_hub_sidebar(lines) then
    stop_project_spinner()
    return
  end
  for _, line in ipairs(section_lines) do
    vim.api.nvim_buf_add_highlight(agent_hub.buf, agent_hub_namespace, "AgentHubSection", line - 1, 0, -1)
  end
  for line, entry in pairs(agent_hub.line_entries) do
    if entry.action == "agent" then
      local status = project_agent_status(entry)
      local group_name = status == "detenido" and "AgentHubStopped" or "AgentHubRunning"
      vim.api.nvim_buf_add_highlight(agent_hub.buf, agent_hub_namespace, group_name, line - 1, 0, -1)
    else
      vim.api.nvim_buf_add_highlight(agent_hub.buf, agent_hub_namespace, "AgentHubHint", line - 1, 0, -1)
    end
  end
  if project_has_executing_agent(group) then
    start_project_spinner()
  else
    stop_project_spinner()
  end
end

stop_project_spinner = function()
  if not spinner_timer then return end
  spinner_timer:stop()
  spinner_timer:close()
  spinner_timer = nil
end

start_project_spinner = function()
  if spinner_timer then return end
  spinner_timer = vim.uv.new_timer()
  spinner_timer:start(0, 140, vim.schedule_wrap(function()
    if not valid_buf(agent_hub.buf) or not agent_hub.project_view or not agent_hub.project_group
        or not agent_hub.sidebar_win or not vim.api.nvim_win_is_valid(agent_hub.sidebar_win) then
      stop_project_spinner()
      return
    end
    spinner_frame = (spinner_frame % #SPINNER_FRAMES) + 1
    if agent_hub.project_view == "menu" then
      render_project_menu(agent_hub.project_group, true)
    else
      render_project_agents(agent_hub.project_group)
    end
  end))
end

stop_hub_spinner = function()
  if not hub_spinner_timer then return end
  hub_spinner_timer:stop()
  hub_spinner_timer:close()
  hub_spinner_timer = nil
end

start_hub_spinner = function()
  if hub_spinner_timer then return end
  hub_spinner_timer = vim.uv.new_timer()
  hub_spinner_timer:start(0, 140, vim.schedule_wrap(function()
    if not valid_buf(agent_hub.buf) or agent_hub.project_view then
      stop_hub_spinner()
      return
    end
    spinner_frame = (spinner_frame % #SPINNER_FRAMES) + 1
    render_agent_hub()
  end))
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

local function toggle_hub_project_pin()
  local entry = selected_hub_entry()
  if not entry or entry.action ~= "project" then
    open_hub_repo_menu()
    return
  end
  if vim.fn.isdirectory(entry.cwd) ~= 1 then
    vim.notify("La carpeta del proyecto no existe", vim.log.levels.WARN)
    return
  end
  local pinned = project_registry.toggle_pin(entry.cwd)
  vim.notify((pinned and "Proyecto fijado con " .. GIT_ICON .. ": " or "Proyecto desfijado: ") .. entry.display_name)
  render_agent_hub()
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
  lines = i18n.translate_lines(lines)
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
  vim.api.nvim_buf_set_name(buf, "Agent Hub Welcome " .. buf)
  render_agent_hub_welcome(buf, width)
  return buf
end

local function create_agent_hub_command_bar()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_name(buf, "Agent Hub Actions " .. buf)
  vim.bo[buf].modifiable = true
  local path = vim.fn.fnamemodify(vim.fn.getcwd(), ":~")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, i18n.translate_lines({
    "  " .. path .. " · Agent Hub",
    "  [ j/k Proyecto ] [ ↵ Cambios ] [ p Abrir ] [ g Fijar/Repos ] [ n Nueva ] [ i Renombrar ] [ ! Detener ] [ d Diff ] [ c Commit ] [ a Copilot ] [ m Expandir ]",
  }))
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
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, i18n.translate_lines({ "  " .. path .. " · Agent Hub" }))
  vim.bo[buf].modifiable = false
end

local function current_changes_title()
  local roots = agent_hub.git_roots or { agent_hub.git_root or vim.fn.getcwd() }
  if agent_hub.selected_git_roots then
    roots = vim.tbl_filter(function(root)
      return agent_hub.selected_git_roots[root] == true
    end, roots)
  end
  return i18n.translate_line(string.format("CAMBIOS  ·  %d repositorio(s)", #roots))
end

local function select_hub_project(entry)
  if not entry or entry.action ~= "project" or entry.cwd == "" then return false end
  agent_hub.git_root = entry.cwd
  add_git_root(entry.cwd)
  agent_hub.selected_project = entry
  style_agent_hub_window(agent_hub.changes_win, current_changes_title(), false)
  refresh_hub_command_bar()
  refresh_hub_changes()
  return true
end

local function resize_hub_window(direction)
  if direction == "left" then
    vim.cmd("vertical resize -5")
  elseif direction == "right" then
    vim.cmd("vertical resize +5")
  elseif direction == "up" then
    vim.cmd("resize -2")
  elseif direction == "down" then
    vim.cmd("resize +2")
  end
end

local function move_hub_window(direction)
  local targets = { left = "h", right = "l", up = "k", down = "j" }
  local target = targets[direction]
  if target then
    vim.cmd("wincmd " .. target)
  end
end

local function arm_hub_control(buf)
  if not valid_buf(buf) then return end

  local directions = {
    ["<Left>"] = "left",
    ["<Right>"] = "right",
    ["<Up>"] = "up",
    ["<Down>"] = "down",
  }
  vim.b[buf].agent_hub_control_mode = "move"

  local function clear_control_maps()
    if not valid_buf(buf) then return end
    vim.b[buf].agent_hub_control_mode = nil
    for key in pairs(directions) do
      pcall(vim.keymap.del, { "n", "t" }, key, { buffer = buf })
    end
    pcall(vim.keymap.del, { "n", "t" }, "r", { buffer = buf })
    pcall(vim.keymap.del, { "n", "t" }, "m", { buffer = buf })
    map_hub_navigation(buf)
    vim.keymap.set("n", "q", close_agent_hub,
      { buffer = buf, desc = "Cerrar AgentHub" })
    vim.keymap.set("n", "<Esc>", restore_hub_layout,
      { buffer = buf, desc = "Restaurar tamaño del Hub" })
  end

  for key, direction in pairs(directions) do
    vim.keymap.set({ "n", "t" }, key, function()
      if vim.b[buf].agent_hub_control_mode == "resize" then
        resize_hub_window(direction)
      else
        move_hub_window(direction)
      end
    end, { buffer = buf, nowait = true, desc = "AgentHub: controlar " .. direction })
  end

  vim.keymap.set({ "n", "t" }, "r", function()
    vim.b[buf].agent_hub_control_mode = "resize"
  end, { buffer = buf, nowait = true, desc = "AgentHub: modo redimensionar" })
  vim.keymap.set({ "n", "t" }, "m", function()
    vim.b[buf].agent_hub_control_mode = "move"
  end, { buffer = buf, nowait = true, desc = "AgentHub: modo mover" })
  vim.keymap.set({ "n", "t" }, "<Esc>", clear_control_maps,
    { buffer = buf, nowait = true, desc = "Salir del modo control del Hub" })
  vim.keymap.set({ "n", "t" }, "q", clear_control_maps,
    { buffer = buf, nowait = true, desc = "Salir del modo control del Hub" })
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

  local leader_directions = {
    ["<leader>a<Left>"] = "left",
    ["<leader>a<Right>"] = "right",
    ["<leader>a<Up>"] = "up",
    ["<leader>a<Down>"] = "down",
  }
  for key, direction in pairs(leader_directions) do
    vim.keymap.set({ "n", "t" }, key, function()
      move_hub_window(direction)
    end, { buffer = buf, desc = "AgentHub: ir " .. direction, nowait = true })
  end

  for _, key in ipairs({ "<C-A>", "<C-@>", "<C-Space>" }) do
    vim.keymap.set({ "n", "t" }, key, function()
      arm_hub_control(buf)
    end, { buffer = buf, desc = "Entrar al modo control del Hub" })
  end
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
    vim.api.nvim_buf_set_name(agent_hub.console_buf, "Agent Hub Console " .. agent_hub.console_buf)
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

-- `return_buf`: buffer al que volver con q/Esc. Al reabrir el menú desde sí
-- mismo ("a") se conserva el panel original en vez del menú anterior.
open_hub_repo_menu = function(return_buf)
  local win = agent_hub.changes_win
  if not (win and vim.api.nvim_win_is_valid(win)) then return end
  local previous = valid_buf(return_buf) and return_buf or vim.api.nvim_win_get_buf(win)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "agent-repositories"
  vim.api.nvim_buf_set_name(buf, "Git Hub Repositories " .. buf)
  local lines = {
    " GIT HUB  ·  REPOSITORIOS ACTIVOS",
    "",
    " Selecciona uno o varios repositorios (Space/Enter marca):",
    "",
  }
  agent_hub.selected_git_roots = agent_hub.selected_git_roots or {}
  for _, root in ipairs(agent_hub.git_roots or {}) do
    if agent_hub.selected_git_roots[root] == nil then
      agent_hub.selected_git_roots[root] = true
    end
  end
  for index, root in ipairs(agent_hub.git_roots or {}) do
    local marker = agent_hub.selected_git_roots[root] and GIT_ICON or "○"
    lines[#lines + 1] = string.format(" %d  %s  %s", index, marker, vim.fn.fnamemodify(root, ":~"))
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = " a  agregar repositorio"
  lines[#lines + 1] = " q  volver a cambios"
  lines = i18n.translate_lines(lines)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_win_set_buf(win, buf)
  vim.b[buf].git_hub_repo_lines = agent_hub.git_roots or {}

  local function restore()
    if vim.api.nvim_win_is_valid(win) and valid_buf(previous) then
      vim.api.nvim_win_set_buf(win, previous)
      style_agent_hub_window(win, current_changes_title(), false)
      refresh_hub_changes()
    end
  end
  vim.keymap.set("n", "q", restore, { buffer = buf, desc = "Volver a cambios Git" })
  vim.keymap.set("n", "<Esc>", restore, { buffer = buf, desc = "Volver a cambios Git" })
  vim.keymap.set("n", "a", function()
    choose_hub_git_folder()
    if vim.api.nvim_win_is_valid(win) then open_hub_repo_menu(previous) end
  end, { buffer = buf, desc = "Agregar repositorio Git" })
  local toggle_repository = function()
    local index = vim.fn.line(".") - 4
    local root = (vim.b[buf].git_hub_repo_lines or {})[index]
    if not root then return end
    agent_hub.selected_git_roots[root] = not agent_hub.selected_git_roots[root]
    agent_hub.git_root = root
    local marker = agent_hub.selected_git_roots[root] and GIT_ICON or "○"
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, index + 3, index + 4, false, {
      string.format(" %d  %s  %s", index, marker, vim.fn.fnamemodify(root, ":~")),
    })
    vim.bo[buf].modifiable = false
    vim.api.nvim_win_set_cursor(win, { index + 4, 0 })
  end
  vim.keymap.set("n", "<CR>", toggle_repository,
    { buffer = buf, desc = "Marcar/desmarcar repositorio" })
  vim.keymap.set("n", "<Space>", toggle_repository,
    { buffer = buf, desc = "Marcar/desmarcar repositorio" })
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
    style_agent_hub_window(agent_hub.changes_win, current_changes_title(), false)
    refresh_hub_changes()
  end
end

local function render_hub_diff(buf, entry)
  local lines = git_output(entry.root, { "diff", "--", entry.path })
  if #lines == 0 then
    lines = git_output(entry.root, { "diff", "--cached", "--", entry.path })
  end
  if #lines == 0 then
    lines = { "", " Sin diff disponible: el archivo es nuevo o no está seguido por Git." }
  end
  table.insert(lines, 1, " q o Esc · volver a cambios   r · actualizar diff")
  lines[1] = i18n.translate_line(lines[1])
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.b[buf].agent_hub_diff_entry = entry
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
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "diff"
  vim.api.nvim_buf_set_name(buf, "Git Diff " .. entry.path)
  render_hub_diff(buf, entry)
  vim.api.nvim_win_set_buf(agent_hub.changes_win, buf)
  style_agent_hub_window(agent_hub.changes_win, "DIFF  ·  " .. entry.path, false)
  vim.wo[agent_hub.changes_win].number = true
  vim.wo[agent_hub.changes_win].relativenumber = false
  vim.wo[agent_hub.changes_win].signcolumn = "yes:1"
  vim.wo[agent_hub.changes_win].foldcolumn = "1"
  vim.wo[agent_hub.changes_win].scrolloff = 3
  vim.wo[agent_hub.changes_win].sidescrolloff = 3
  vim.keymap.set("n", "q", return_to_hub_changes, { buffer = buf, desc = "Volver a cambios Git" })
  vim.keymap.set("n", "<Esc>", return_to_hub_changes, { buffer = buf, desc = "Volver a cambios Git" })
  vim.keymap.set("n", "<leader>gb", return_to_hub_changes,
    { buffer = buf, desc = "Git: volver al árbol de cambios" })
  vim.keymap.set("n", "r", function()
    local current = vim.b[buf].agent_hub_diff_entry
    if current then render_hub_diff(buf, current) end
  end, { buffer = buf, desc = "Actualizar diff" })
  return true
end

local function commit_hub_changes()
  local changes_buf = agent_hub.changes_buf
  if type(changes_buf) ~= "number" or not vim.api.nvim_buf_is_valid(changes_buf) then
    vim.notify("El panel de cambios ya no está disponible. Pulsa r para actualizar.", vim.log.levels.WARN)
    return
  end
  local line = vim.fn.line(".")
  local file_lines = vim.b[changes_buf].agent_hub_changed_files
  local folder_lines = vim.b[changes_buf].agent_hub_change_folders
  local file_entry = type(file_lines) == "table" and file_lines[line] or nil
  local folder_entry = type(folder_lines) == "table" and folder_lines[line] or nil
  local selected = (type(file_entry) == "table" and file_entry)
    or (type(folder_entry) == "table" and folder_entry)
    or nil
  local root = selected and type(selected.root) == "string" and selected.root
    or (type(agent_hub.git_root) == "string" and agent_hub.git_root or vim.fn.getcwd())
  require("config.git_commit").open(root, function()
    if not is_shutting_down then return_to_hub_changes() end
  end, agent_hub.changes_win)
end

restore_hub_layout = function()
  if agent_hub.maximized then
    vim.cmd("wincmd =")
    agent_hub.maximized = false
    if layout_agent_hub then layout_agent_hub(true) end
    return true
  end
  return false
end

local function toggle_hub_maximize()
  save_hub_layout()
  if not restore_hub_layout() then
    vim.cmd("wincmd |")
    vim.cmd("wincmd _")
    agent_hub.maximized = true
  end
end

layout_agent_hub = function(force)
  if agent_hub.maximized then return end
  if agent_hub.layout_initialized and not force then return end
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
  local default_sidebar_width = math.min(36, math.max(28, math.floor(columns * 0.20)))
  local default_changes_width = math.min(42, math.max(30, math.floor(columns * 0.24)))
  local sidebar_width = saved_hub_layout.sidebar_width or default_sidebar_width
  local changes_width = saved_hub_layout.changes_width or default_changes_width
  local command_height = saved_hub_layout.command_height or 2
  pcall(vim.api.nvim_win_set_width, sidebar, sidebar_width)
  pcall(vim.api.nvim_win_set_width, changes, changes_width)
  pcall(vim.api.nvim_win_set_height, command, command_height)
  agent_hub.layout_initialized = true
  save_hub_layout()
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
  local current_root = normalize_project_path(vim.fn.getcwd())
  local registered_roots = registered_project_roots()
  if not vim.tbl_contains(registered_roots, current_root) then
    table.insert(registered_roots, current_root)
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
    git_root = current_root,
    git_roots = registered_roots,
    collapsed_directories = {},
  }
  style_agent_hub_window(sidebar_win, "AGENT HUB  ·  sesiones", true)
  style_agent_hub_window(changes_win, current_changes_title(), false)
  style_agent_hub_window(command_win, "ACCIONES", false)
  style_agent_hub_window(agent_win, "BIENVENIDO", false)
  layout_agent_hub()
  render_agent_hub_welcome(welcome_buf, vim.api.nvim_win_get_width(agent_win))
  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("AgentHubWelcomeCentering", { clear = true }),
    callback = function()
      if valid_buf(agent_hub.welcome_buf)
          and agent_hub.agent_win and vim.api.nvim_win_is_valid(agent_hub.agent_win) then
        save_hub_layout()
        render_agent_hub_welcome(agent_hub.welcome_buf, vim.api.nvim_win_get_width(agent_hub.agent_win))
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinResized", {
    group = vim.api.nvim_create_augroup("AgentHubWelcomeWinCentering", { clear = true }),
    callback = function()
      save_hub_layout()
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
    if entry and (entry.action == "project" or entry.action == "project_open") then
      require("config.projects").open(entry.cwd)
    end
  end

  local function open_selected_agent()
    local entry = selected_hub_entry()
    if not entry then return end
    if entry.action == "project" then
      render_project_menu(entry)
    elseif entry.action == "project_open" then
      open_selected_project()
    elseif entry.action == "project_agents" then
      render_project_agents(entry.group)
    elseif entry.action == "new" then
      start_new_instance(entry.name, entry.cmd)
    elseif entry.action == "agent" then
      activate_hub_agent(entry.name, entry.cmd, entry.cwd, entry.external)
      style_agent_hub_window(agent_win, entry.name:upper(), false)
    end
  end

  local function leave_project_view()
    if agent_hub.project_view == "agents" and agent_hub.project_group then
      render_project_menu(agent_hub.project_group)
    elseif agent_hub.project_view == "menu" then
      render_agent_hub()
    else
      close_agent_hub()
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

  local function delete_project_agent()
    if agent_hub.project_view ~= "agents" or not agent_hub.project_group then return end
    local entry = selected_hub_entry()
    if not entry or entry.action ~= "agent" then return end
    vim.ui.select({ "Eliminar", "Cancelar" }, {
      prompt = "Eliminar esta sesión del proyecto?",
    }, function(choice)
      if choice ~= "Eliminar" then return end
      if entry.external then
        if not agent_sessions.remove(entry) then
          vim.notify("No se pudo eliminar la sesión " .. (entry.kind or "externa"), vim.log.levels.WARN)
          return
        end
      elseif state[entry.name] then
        stop_agent(entry.name)
      end
      local sessions = agent_hub.project_group.sessions or {}
      agent_hub.project_group.sessions = vim.tbl_filter(function(session)
        return session.session_id ~= entry.session_id and session.name ~= entry.name
      end, sessions)
      render_project_agents(agent_hub.project_group)
    end)
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
    if entry and entry.action ~= "noop" then
      agent_hub.selection = entry
      show_hub_hover(entry)
    else
      agent_hub.selection = nil
      close_hub_hover()
    end
  end

  vim.opt.mousemoveevent = true
  local hover_events = { "CursorMoved" }
  if vim.fn.exists("##MouseMoved") == 1 then
    table.insert(hover_events, "MouseMoved")
  end
  vim.api.nvim_create_autocmd(hover_events, {
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
  vim.keymap.set("n", "g", toggle_hub_project_pin,
    { buffer = sidebar_buf, desc = "Fijar proyecto o elegir repositorios Git" })
  vim.keymap.set("n", "d", function()
    if agent_hub.project_view == "agents" then
      delete_project_agent()
    else
      local entry = selected_hub_entry()
      if entry and entry.action == "agent" then show_agent_diff(entry.name) end
    end
  end, { buffer = sidebar_buf, desc = "Ver diff o eliminar agente del proyecto" })
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
    vim.keymap.set("n", "g", function() open_hub_repo_menu() end,
      { buffer = buf, desc = "Seleccionar repositorio Git" })
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
    local mouse = vim.fn.getmousepos()
    local win = mouse.winid
    if win == 0 or not vim.api.nvim_win_is_valid(win) then
      win = vim.api.nvim_get_current_win()
    end
    if mouse.line < 1 or vim.api.nvim_win_get_buf(win) ~= changes_buf then return end
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_cursor(win, { mouse.line, 0 })
    if not toggle_changes_folder(changes_buf) and not run_changes_button() then open_hub_changed_file() end
  end, { buffer = changes_buf, desc = "Pulsar botón de cambios", nowait = true, silent = true })
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
  vim.keymap.set("n", "q", leave_project_view, { buffer = sidebar_buf, desc = "Volver en la vista de proyecto" })

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
  stop_project_spinner()
  stop_hub_spinner()
  save_hub_layout()
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
  vim.api.nvim_buf_set_name(buf, "Agent Terminal " .. name .. " " .. buf)
  map_hub_navigation(buf)
  local function current_name()
    return session_name_for_buf(buf, name)
  end
  vim.fn.termopen(cmd, {
    cwd = cwd,
    on_exit = function()
      if is_shutting_down then return end
      vim.schedule(function()
        if is_shutting_down then return end
        -- Por buffer, no por nombre: la sesión pudo renombrarse, o ya se
        -- detuvo y otra nueva reutiliza el mismo nombre.
        local current = session_name_for_buf(buf)
        if not current then return end
        if agent_hub.active == current and agent_hub.agent_win and vim.api.nvim_win_is_valid(agent_hub.agent_win) then
          vim.api.nvim_win_set_buf(agent_hub.agent_win, hub_welcome_buffer())
          agent_hub.active = nil
          style_agent_hub_window(agent_hub.agent_win, "BIENVENIDO", false)
        end
        state[current] = nil
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
    toggle_tool(current_name(), cmd)
  end, { buffer = buf, desc = "Ocultar " .. name })
  vim.keymap.set("n", "d", function()
    show_agent_diff(current_name())
  end, { buffer = buf, desc = "Ver cambios de " .. name .. " (Diffview)" })
  vim.keymap.set({ "n", "t" }, "<A-q>", function()
    toggle_tool(current_name(), cmd)
  end, { buffer = buf, desc = "Ocultar " .. name })
  vim.keymap.set({ "n", "t" }, "<A-d>", function()
    show_agent_diff(current_name())
  end, { buffer = buf, desc = "Ver cambios de " .. name .. " (Diffview)" })
  vim.keymap.set({ "n", "t" }, "<A-k>", function()
    stop_agent(current_name())
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
      -- true elimina este autocmd cuando la sesión ya no existe.
      if not session_name_for_buf(buf) then return true end
      vim.schedule(function()
        if is_shutting_down then return end
        local current = session_name_for_buf(buf)
        local session = current and state[current]
        if not session or session_is_visible(session) then return end
        if agent_hub.active == current then
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

STATUS_ICON = { visible = "●", activo = "●", ejecutando = "●", oculto = "○", disponible = "◇", detenido = "◌" }

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

vim.api.nvim_create_user_command("Grok", tool_command("Grok", "grok"),
  { nargs = "*", bang = true, desc = "Mostrar/ocultar Grok CLI (! = nueva instancia)" })

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
vim.cmd("cnoreabbrev grok Grok")
vim.cmd("cnoreabbrev agents Agents")
vim.cmd("cnoreabbrev agentdiff AgentDiff")
vim.cmd("cnoreabbrev agentkill AgentKill")
vim.cmd("cnoreabbrev agentskillall AgentsKillAll")

return {}
