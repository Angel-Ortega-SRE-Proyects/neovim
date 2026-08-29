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

local state = {} -- name -> { buf, win }
-- forward-declarados: toggle_tool los referencia (en los binds Alt-k/Alt-a)
-- antes de que se definan más abajo en el archivo.
local open_agents_picker
local open_agent_hub
local stop_agent
local toggle_tool
local start_new_instance
local agent_status
local STATUS_ICON

-- Empuja los conteos a config/agents_status.lua para que la statusline
-- pinte el indicador (●N visibles, ○N ocultos) sin tener que importar todo
-- este archivo. Se llama en cada mutación de `state`.
local function publish_status()
  local visible, hidden = 0, 0
  for _, s in pairs(state) do
    if s.win and vim.api.nvim_win_is_valid(s.win) then
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

local function changes_tree(files)
  local root = {}
  for _, file in ipairs(files) do
    local status, path = file:sub(1, 2), file:sub(4)
    local node = root
    for part in path:gmatch("[^/]+") do
      node[part] = node[part] or {}
      node = node[part]
    end
    node.status = status
  end

  local lines = { "", " ARCHIVOS MODIFICADOS" }
  local function append(node, prefix)
    local names = vim.tbl_keys(node)
    table.sort(names)
    for _, name in ipairs(names) do
      if name ~= "status" then
        local child = node[name]
        local is_file = child.status ~= nil
        table.insert(lines, string.format(" %s%s%s", prefix, is_file and "• " or "▸ ", name))
        if is_file then
          lines[#lines] = lines[#lines] .. "  " .. child.status
        else
          append(child, prefix .. "  ")
        end
      end
    end
  end
  append(root, "")
  return lines
end

local function changes_panel_lines(root)
  root = root or vim.fn.getcwd()
  local files = git_output(root, { "status", "--short" })
  if vim.v.shell_error ~= 0 then
    return {
      " CAMBIOS",
      "",
      "  ╭─[ g · ELEGIR CARPETA GIT ]────╮",
      "  ├─[ r · ACTUALIZAR CAMBIOS ]─────┤",
      "  ╰─[ Ctrl-P · BUSCAR ARCHIVOS ]───╯",
    }
  end

  local lines = {
    " CAMBIOS",
    "",
    "  ╭─[ g · ELEGIR CARPETA GIT ]────╮",
    "  ├─[ r · ACTUALIZAR CAMBIOS ]─────┤",
    "  ╰─[ Ctrl-P · BUSCAR ARCHIVOS ]───╯",
    "",
    " " .. root,
  }
  if #files == 0 then
    table.insert(lines, "")
    table.insert(lines, " Sin archivos modificados")
    return lines
  end

  vim.list_extend(lines, changes_tree(files))

  local summary = git_output(root, { "diff", "--stat" })
  if #summary > 0 then
    table.insert(lines, "")
    table.insert(lines, " Diff summary")
    for _, line in ipairs(summary) do
      table.insert(lines, " " .. line)
    end
  end
  return lines
end

local function refresh_changes_panel(buf, root)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, changes_panel_lines(root))
    vim.bo[buf].modifiable = false
  end
end

local function create_changes_panel()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "agent-changes"
  vim.api.nvim_buf_set_name(buf, "Agent Changes")
  refresh_changes_panel(buf)
  vim.keymap.set("n", "r", function()
    refresh_changes_panel(buf)
  end, { buffer = buf, desc = "Actualizar cambios Git" })
  return buf
end

-- Convierte una sesión existente (o recién iniciada) en una vista estable de
-- dos columnas, similar a chat + Changes de editores gráficos. El terminal
-- sigue siendo el mismo buffer/proceso: no reinicia ni pierde el contexto.
local function open_agent_workspace(name, cmd)
  if not state[name] then
    toggle_tool(name, cmd)
  end

  local s = state[name]
  if not s or not (s.buf and vim.api.nvim_buf_is_valid(s.buf)) then
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
local agent_hub = {}
local agent_hub_namespace = vim.api.nvim_create_namespace("agent-hub")

local function setup_agent_hub_highlights()
  vim.api.nvim_set_hl(0, "AgentHubTitle", { link = "Title" })
  vim.api.nvim_set_hl(0, "AgentHubSection", { link = "Special" })
  vim.api.nvim_set_hl(0, "AgentHubHint", { link = "Comment" })
  vim.api.nvim_set_hl(0, "AgentHubActive", { link = "Visual" })
  vim.api.nvim_set_hl(0, "AgentHubRunning", { link = "DiagnosticOk" })
  vim.api.nvim_set_hl(0, "AgentHubStopped", { link = "Comment" })
  vim.api.nvim_set_hl(0, "AgentHubAction", { link = "String" })
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

local function hub_entries()
  local entries = {}
  for _, agent in ipairs(AGENTS) do
    table.insert(entries, { name = agent.name, cmd = agent.cmd, action = "agent" })
  end
  for name, s in pairs(state) do
    if not vim.tbl_contains(vim.tbl_map(function(agent) return agent.name end, AGENTS), name) then
      table.insert(entries, { name = name, cmd = s.cmd, action = "agent" })
    end
  end
  table.sort(entries, function(left, right) return left.name < right.name end)
  return entries
end

local function render_agent_hub()
  local buf = agent_hub.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end

  local lines = {
    "  AGENT HUB",
    "  Sesiones disponibles",
    "",
    "  SESIONES",
  }
  agent_hub.line_entries = {}
  for _, entry in ipairs(hub_entries()) do
    local status = agent_status(entry.name)
    local selected = entry.name == agent_hub.active and ">" or " "
    table.insert(lines, string.format(" %s %s %-18s %s", selected, STATUS_ICON[status], entry.name, status))
    agent_hub.line_entries[#lines] = entry
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
    elseif entry.name == agent_hub.active then
      vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubActive", row, 0, -1)
    elseif agent_status(entry.name) == "detenido" then
      vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubStopped", row, 0, -1)
    else
      vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubRunning", row, 0, -1)
    end
  end
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubSection", #lines - #AGENTS - 1, 0, -1)
end

local function activate_hub_agent(name, cmd)
  local hub_win = agent_hub.agent_win
  if not (hub_win and vim.api.nvim_win_is_valid(hub_win)) then
    return
  end

  local previous = agent_hub.active and state[agent_hub.active]
  if previous and previous.win == hub_win then
    previous.win = nil
  end

  if not state[name] then
    toggle_tool(name, cmd)
  end
  local s = state[name]
  if not s or not (s.buf and vim.api.nvim_buf_is_valid(s.buf)) then
    return
  end
  if s.win and vim.api.nvim_win_is_valid(s.win) and s.win ~= hub_win then
    vim.api.nvim_win_close(s.win, true)
  end

  vim.api.nvim_win_set_buf(hub_win, s.buf)
  s.win = hub_win
  agent_hub.active = name
  render_agent_hub()
  vim.api.nvim_set_current_win(hub_win)
  vim.cmd("startinsert")
  publish_status()
end

local function show_agent_in_hub(name, cmd)
  if not (agent_hub.tabpage and vim.api.nvim_tabpage_is_valid(agent_hub.tabpage)
      and agent_hub.agent_win and vim.api.nvim_win_is_valid(agent_hub.agent_win)) then
    return false
  end
  vim.api.nvim_set_current_tabpage(agent_hub.tabpage)
  activate_hub_agent(name, cmd)
  return true
end

local function selected_hub_entry()
  return agent_hub.line_entries and (agent_hub.line_entries[vim.fn.line(".")] or agent_hub.selection)
end

local function create_agent_hub_welcome()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "",
    "                         AGENT HUB",
    "",
    "          Elige una sesión en el panel izquierdo para comenzar.",
    "",
    "     ⏎  abrir agente      n  nueva instancia",
    "",
    "     La terminal no se inicia hasta que tú la selecciones.",
  })
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubTitle", 1, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubHint", 3, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubAction", 5, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubHint", 7, 0, -1)
  return buf
end

local function create_agent_hub_command_bar()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "  [ ↵ Abrir ]  [ n Nueva ]  [ ! Detener ]  [ d Diff ]  [ g Carpeta Git ]  [ m Expandir ]",
  })
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubAction", 0, 0, -1)
  return buf
end

local function refresh_hub_changes()
  refresh_changes_panel(agent_hub.changes_buf, agent_hub.git_root)
  local buf = agent_hub.changes_buf
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, agent_hub_namespace, 0, -1)
    for row = 2, 4 do
      vim.api.nvim_buf_add_highlight(buf, agent_hub_namespace, "AgentHubAction", row, 0, -1)
    end
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
  agent_hub.git_root = root[1]
  refresh_hub_changes()
end

local function search_hub_files()
  local ok, builtin = pcall(require, "telescope.builtin")
  if not ok then
    vim.notify("La búsqueda de archivos necesita telescope.nvim", vim.log.levels.ERROR)
    return
  end
  builtin.git_files({
    cwd = agent_hub.git_root,
    prompt_title = "Archivos del repositorio",
    show_untracked = true,
    previewer = true,
  })
end

local function restore_hub_layout()
  if agent_hub.maximized then
    vim.cmd("wincmd =")
    agent_hub.maximized = false
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

open_agent_hub = function()
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
  vim.api.nvim_buf_set_name(sidebar_buf, "Agent Hub")
  vim.api.nvim_win_set_buf(sidebar_win, sidebar_buf)
  vim.cmd("botright 2new")
  local command_win = vim.api.nvim_get_current_win()
  local command_placeholder = vim.api.nvim_get_current_buf()

  setup_agent_hub_highlights()
  local welcome_buf = create_agent_hub_welcome()
  local command_buf = create_agent_hub_command_bar()
  vim.api.nvim_win_set_buf(agent_win, welcome_buf)
  vim.api.nvim_win_set_buf(command_win, command_buf)
  for _, placeholder in ipairs({ agent_placeholder, sidebar_placeholder, command_placeholder }) do
    if vim.api.nvim_buf_is_valid(placeholder)
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
  }
  style_agent_hub_window(sidebar_win, "AGENT HUB  ·  sesiones", true)
  style_agent_hub_window(changes_win, "CAMBIOS  ·  Git", false)
  style_agent_hub_window(command_win, "ACCIONES", false)
  style_agent_hub_window(agent_win, "BIENVENIDO", false)
  vim.api.nvim_win_set_width(sidebar_win, 36)
  vim.api.nvim_win_set_width(changes_win, math.max(32, math.floor(vim.o.columns * 0.25)))
  vim.api.nvim_win_set_height(command_win, 2)
  refresh_hub_changes()

  local function open_selected_agent()
    local entry = selected_hub_entry()
    if not entry then return end
    if entry.action == "new" then
      start_new_instance(entry.name, entry.cmd)
    else
      activate_hub_agent(entry.name, entry.cmd)
      style_agent_hub_window(agent_win, entry.name:upper(), false)
    end
  end

  local function stop_selected_agent()
    local entry = selected_hub_entry()
    if not entry or entry.action ~= "agent" or not state[entry.name] then return end
    local s = state[entry.name]
    if s.win == agent_hub.agent_win then
      s.win = nil
      vim.api.nvim_win_set_buf(agent_hub.agent_win, agent_hub.welcome_buf)
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
      choose_hub_git_folder()
    elseif row == 4 then
      refresh_hub_changes()
    elseif row == 5 then
      search_hub_files()
    else
      return false
    end
    return true
  end

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = sidebar_buf,
    callback = function()
      local entry = agent_hub.line_entries and agent_hub.line_entries[vim.fn.line(".")]
      if entry then agent_hub.selection = entry end
    end,
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
  vim.keymap.set("n", "d", function()
    local entry = selected_hub_entry()
    if entry and entry.action == "agent" then show_agent_diff(entry.name) end
  end, { buffer = sidebar_buf, desc = "Ver cambios del agente" })
  vim.keymap.set("n", "r", function()
    refresh_hub_changes()
    render_agent_hub()
  end, { buffer = sidebar_buf, desc = "Actualizar paneles" })
  vim.keymap.set("n", "t", function()
    if agent_hub.active and vim.api.nvim_win_is_valid(agent_win) then
      vim.api.nvim_set_current_win(agent_win)
      vim.cmd("startinsert")
    end
  end, { buffer = sidebar_buf, desc = "Ir a terminal activa" })
  vim.keymap.set("n", "g", choose_hub_git_folder, { buffer = sidebar_buf, desc = "Elegir carpeta Git" })
  vim.keymap.set("n", "m", toggle_hub_maximize, { buffer = sidebar_buf, desc = "Maximizar/restaurar panel" })

  for _, buf in ipairs({ changes_buf, command_buf }) do
    vim.keymap.set("n", "<CR>", open_selected_agent, { buffer = buf, desc = "Abrir agente seleccionado" })
    vim.keymap.set("n", "n", create_new_agent_instance, { buffer = buf, desc = "Crear nueva instancia" })
    vim.keymap.set("n", "!", stop_selected_agent, { buffer = buf, desc = "Detener agente seleccionado" })
    vim.keymap.set("n", "d", function()
      local entry = selected_hub_entry()
      if entry and entry.action == "agent" then show_agent_diff(entry.name) end
    end, { buffer = buf, desc = "Ver diff del agente seleccionado" })
    vim.keymap.set("n", "g", choose_hub_git_folder, { buffer = buf, desc = "Elegir carpeta Git" })
    vim.keymap.set("n", "r", refresh_hub_changes, { buffer = buf, desc = "Actualizar cambios" })
    vim.keymap.set("n", "m", toggle_hub_maximize, { buffer = buf, desc = "Maximizar/restaurar panel" })
  end
  vim.keymap.set("n", "<C-p>", search_hub_files, { buffer = changes_buf, desc = "Buscar archivos del repositorio Git" })
  vim.keymap.set("n", "<CR>", function()
    if not run_changes_button() then open_selected_agent() end
  end, { buffer = changes_buf, desc = "Ejecutar botón de cambios" })
  vim.keymap.set("n", "<LeftMouse>", function()
    run_changes_button()
  end, { buffer = changes_buf, desc = "Pulsar botón de cambios" })
  for _, buf in ipairs({ sidebar_buf, changes_buf, command_buf, welcome_buf }) do
    vim.keymap.set("n", "<Esc>", restore_hub_layout, { buffer = buf, desc = "Restaurar tamaño del Hub" })
  end

  render_agent_hub()
  vim.api.nvim_set_current_win(sidebar_win)
end

toggle_tool = function(name, cmd)
  local s = state[name]

  if s and s.win and vim.api.nvim_win_is_valid(s.win) then
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

  if s and s.buf and vim.api.nvim_buf_is_valid(s.buf) then
    s.win = vim.api.nvim_open_win(s.buf, true, float_opts(name))
    vim.cmd("startinsert")
    publish_status()
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, float_opts(name))
  vim.fn.termopen(cmd, {
    on_exit = function()
      state[name] = nil
      publish_status()
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
  state[name] = { buf = buf, win = win, cmd = cmd, dirty_before = dirty_files_set() or {} }
  vim.cmd("startinsert")
  publish_status()
end

-- Para el picker: si ya está visible, solo enfoca (no la oculta, a
-- diferencia de toggle_tool que es on/off para el atajo directo).
local function focus_or_start(name, cmd)
  local s = state[name]
  if s and s.win and vim.api.nvim_win_is_valid(s.win) then
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
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    return "visible"
  end
  return "oculto"
end

stop_agent = function(name)
  local s = state[name]
  if not s then
    return
  end
  if s.buf and vim.api.nvim_buf_is_valid(s.buf) then
    local job = vim.b[s.buf].terminal_job_id
    if job then
      vim.fn.jobstop(job)
    end
  end
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_close(s.win, true)
  end
  close_changes_panel(s)
  state[name] = nil
  publish_status()
end

STATUS_ICON = { visible = "●", oculto = "○", detenido = "◌" }

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
    if s.buf and vim.api.nvim_buf_is_valid(s.buf) then
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
    if cmd_opts.bang then
      start_new_instance(base, full)
    elseif not show_agent_in_hub(base, full) then
      toggle_tool(base, full)
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

vim.keymap.set("n", "<leader>ac", "<cmd>Claude<CR>", { desc = "Claude Code (toggle)" })
vim.keymap.set("n", "<leader>ax", "<cmd>Codex<CR>", { desc = "Codex CLI (toggle)" })
vim.keymap.set("n", "<leader>ao", "<cmd>OpenCode<CR>", { desc = "OpenCode CLI (toggle)" })
vim.keymap.set("n", "<leader>ag", "<cmd>Gemini<CR>", { desc = "Gemini (toggle)" })
vim.keymap.set("n", "<leader>aC", "<cmd>CopilotCli<CR>", { desc = "GitHub Copilot CLI (toggle)" })
vim.keymap.set("n", "<leader>aa", open_agent_hub, { desc = "Hub de agentes" })
vim.keymap.set("n", "<leader>aw", function()
  open_agent_workspace_picker("")
end, { desc = "Agente + cambios Git a pantalla completa" })
vim.keymap.set("n", "<leader>ad", "<cmd>AgentDiff<CR>", { desc = "Ver diff del agente actual" })
vim.keymap.set("n", "<leader>ak", "<cmd>AgentKill<CR>", { desc = "Matar el agente actual" })
vim.keymap.set("n", "<leader>aK", "<cmd>AgentsKillAll<CR>", { desc = "Matar TODOS los agentes" })

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
