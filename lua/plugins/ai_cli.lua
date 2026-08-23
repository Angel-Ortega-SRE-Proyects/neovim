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
--   q  (dentro del flotante, en modo normal)   también lo oculta
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

local AGENTS = {
  { name = "Claude Code", cmd = "claude" },
  { name = "Codex", cmd = "codex" },
  { name = "OpenCode", cmd = "opencode" },
}

local state = {} -- name -> { buf, win }

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
    title = string.format(" %s (q para ocultar) ", name),
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
    return
  end

  if s and s.buf and vim.api.nvim_buf_is_valid(s.buf) then
    s.win = vim.api.nvim_open_win(s.buf, true, float_opts(name))
    vim.cmd("startinsert")
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, float_opts(name))
  vim.fn.termopen(cmd, {
    on_exit = function()
      state[name] = nil
    end,
  })
  vim.keymap.set("n", "q", function()
    toggle_tool(name, cmd)
  end, { buffer = buf, desc = "Ocultar " .. name })
  state[name] = { buf = buf, win = win }
  vim.cmd("startinsert")
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

local function stop_agent(name)
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

local function open_agents_picker()
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
    prompt_title = "Agentes de IA (Enter: ir/arrancar, <C-x>: matar)",
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
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry().value
        actions.close(prompt_bufnr)
        if entry.action == "new" then
          focus_or_start(next_instance_name(entry.base), entry.cmd)
        else
          focus_or_start(entry.name, entry.cmd)
        end
      end)
      map({ "i", "n" }, "<C-x>", function()
        local entry = action_state.get_selected_entry().value
        if entry.action ~= "new" then
          stop_agent(entry.name)
        end
        actions.close(prompt_bufnr)
        open_agents_picker()
      end)
      return true
    end,
  }):find()
end

local function tool_command(base, bin)
  return function(cmd_opts)
    local name = cmd_opts.bang and next_instance_name(base) or base
    toggle_tool(name, vim.trim(bin .. " " .. cmd_opts.args))
  end
end

vim.api.nvim_create_user_command("Claude", tool_command("Claude Code", "claude"),
  { nargs = "*", bang = true, desc = "Mostrar/ocultar Claude Code (! = nueva instancia)" })

vim.api.nvim_create_user_command("Codex", tool_command("Codex", "codex"),
  { nargs = "*", bang = true, desc = "Mostrar/ocultar Codex (! = nueva instancia)" })

vim.api.nvim_create_user_command("OpenCode", tool_command("OpenCode", "opencode"),
  { nargs = "*", bang = true, desc = "Mostrar/ocultar OpenCode (! = nueva instancia)" })

vim.api.nvim_create_user_command("Agents", open_agents_picker, { desc = "Picker de sesiones de IA activas" })

vim.keymap.set("n", "<leader>ac", "<cmd>Claude<CR>", { desc = "Claude Code (toggle)" })
vim.keymap.set("n", "<leader>ax", "<cmd>Codex<CR>", { desc = "Codex CLI (toggle)" })
vim.keymap.set("n", "<leader>ao", "<cmd>OpenCode<CR>", { desc = "OpenCode CLI (toggle)" })
vim.keymap.set("n", "<leader>aa", open_agents_picker, { desc = "Modo agentes (picker de sesiones)" })

-- Vim exige mayúscula inicial en comandos de usuario (:Claude, no :claude);
-- estas abreviaciones de línea de comandos permiten escribir en minúscula
-- como el binario real, sin duplicar la definición del comando.
vim.cmd("cnoreabbrev claude Claude")
vim.cmd("cnoreabbrev codex Codex")
vim.cmd("cnoreabbrev opencode OpenCode")
vim.cmd("cnoreabbrev agents Agents")

return {}
