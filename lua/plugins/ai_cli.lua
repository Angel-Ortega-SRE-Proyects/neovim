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
--   q  (dentro del flotante, en modo normal)   también lo oculta
--   Alt-q / Alt-d / Alt-k   ocultar/diff/matar SIN salir del modo terminal
--      -- ojo con <C-d> "pelado": eso NO lo intercepta Neovim, se lo manda
--      tal cual al proceso (Claude/Codex lo pueden leer como EOF y cerrar
--      la sesión), por eso estos atajos usan Alt en vez de Ctrl.
--   Alt-a   el mismo picker de <leader>aa (ver abajo), pero sin salir del
--      agente en el que estás -- Alt adentro se comporta como <leader>
--      afuera.
--
--   <leader>aa   "Modo agentes": picker (Telescope) con TODAS las sesiones
--                -- corriendo visible, corriendo oculta, o sin arrancar --
--                Enter salta a esa (arrancándola si hace falta), <C-x> la
--                mata del todo. Ideal para saltar entre varias sin ir
--                probando tecla por tecla.
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

local AGENTS = {
  { name = "Claude Code", cmd = "claude" },
  { name = "Codex", cmd = "codex" },
  { name = "OpenCode", cmd = "opencode" },
  { name = "Gemini", cmd = "gemini" },
}

local state = {} -- name -> { buf, win }
-- forward-declarados: toggle_tool los referencia (en los binds Alt-k/Alt-a)
-- antes de que se definan más abajo en el archivo.
local open_agents_picker
local stop_agent

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

local function toggle_tool(name, cmd)
  local s = state[name]

  if s and s.win and vim.api.nvim_win_is_valid(s.win) then
    -- force=true: los buffers de terminal quedan "modificados" (hay
    -- contenido sin guardar) apenas el proceso escribe algo, así que sin
    -- forzar Vim bloquea el cierre con E37/E162 -- no hay nada que
    -- "guardar" en una terminal, así que forzar acá es seguro.
    vim.api.nvim_win_close(s.win, true)
    s.win = nil
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
  -- Alt-a = el mismo picker que <leader>aa desde afuera, pero alcanzable
  -- sin salir del agente en el que estás parado.
  vim.keymap.set({ "n", "t" }, "<A-a>", function()
    open_agents_picker()
  end, { buffer = buf, desc = "Modo agentes (picker)" })
  state[name] = { buf = buf, win = win, dirty_before = dirty_files_set() or {} }
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
local function start_new_instance(base, cmd)
  vim.ui.input({ prompt = "Nombre para la nueva instancia de " .. base .. ": ", default = next_instance_name(base) }, function(input)
    if input and input ~= "" then
      focus_or_start(input, cmd)
    end
  end)
end

local function agent_status(name)
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
  state[name] = nil
  publish_status()
end

local STATUS_ICON = { visible = "●", oculto = "○", detenido = "◌" }

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
    else
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

vim.api.nvim_create_user_command("Agents", open_agents_picker, { desc = "Picker de sesiones de IA activas" })

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
vim.keymap.set("n", "<leader>aa", open_agents_picker, { desc = "Modo agentes (picker de sesiones)" })
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
vim.cmd("cnoreabbrev agents Agents")
vim.cmd("cnoreabbrev agentdiff AgentDiff")
vim.cmd("cnoreabbrev agentkill AgentKill")
vim.cmd("cnoreabbrev agentskillall AgentsKillAll")

return {}
