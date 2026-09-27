-- Terminales, sincronizadas en ambas direcciones con el cwd de Neovim (y
-- por lo tanto con el explorador, que sigue al cwd) — ver
-- lua/config/autocmds.lua para el mecanismo de sincronización (OSC 7).
--
--   :Term    terminal como pestaña normal (buffer en el área de edición,
--            aparece en la barra de buffers igual que un archivo) — vive
--            y muere con Neovim, es una terminal interna.
--   :Tb      pane de tmux REAL, dividido debajo del pane donde corre
--            Neovim (requiere estar dentro de una sesión de tmux). No es
--            una terminal de Neovim: es un pane hermano, así que sigue
--            vivo aunque cierres/crashee Neovim, y se navega a él con los
--            mismos <C-Flechas> de smart-splits.nvim (multiplexer_integration
--            = "tmux"), no con un atajo aparte.
--
-- Uso:
--   <leader>tt       abrir/enfocar terminal en pestaña
--   :Term ls -la     abre la pestaña y ejecuta ese comando
--   :Tb ls -la       abre el pane de tmux y ejecuta ese comando
local term_bufnr = nil

local function open_tab_terminal(args)
  if term_bufnr and vim.api.nvim_buf_is_valid(term_bufnr) then
    local win = vim.fn.bufwinid(term_bufnr)
    if win == -1 then
      vim.cmd("tabnew")
      vim.cmd("buffer " .. term_bufnr)
    else
      vim.api.nvim_set_current_win(win)
    end
  else
    -- La terminal vive en una pestaña dedicada para no mezclarla con el
    -- explorador ni con los splits del proyecto activo.
    vim.cmd("tabnew")
    vim.fn.termopen(vim.o.shell)
    term_bufnr = vim.api.nvim_get_current_buf()
  end
  vim.cmd("startinsert")

  if args ~= "" then
    vim.defer_fn(function()
      local job = vim.b[term_bufnr].terminal_job_id
      if job then
        vim.fn.chansend(job, args .. "\n")
      end
    end, 60)
  end
end

vim.api.nvim_create_user_command("Term", function(cmd_opts)
  open_tab_terminal(cmd_opts.args)
end, { nargs = "*", desc = "Terminal como pestaña (opcional: comando a ejecutar)" })

-- :Tb -> pane de tmux real abajo (no una terminal interna de Neovim). Se
-- guarda el pane_id la primera vez; si ya existe se reusa/enfoca en vez de
-- crear otro, y si lo cerraste desde tmux (list-panes ya no lo tiene) se
-- vuelve a crear.
local tmux_bottom_pane_id = nil

local function tmux_pane_exists(id)
  if not id then
    return false
  end
  local panes = vim.fn.system({ "tmux", "list-panes", "-a", "-F", "#{pane_id}" })
  return panes:find(id, 1, true) ~= nil
end

vim.api.nvim_create_user_command("Tb", function(cmd_opts)
  if vim.env.TMUX == nil then
    vim.notify("Tb necesita Neovim corriendo dentro de una sesión de tmux", vim.log.levels.WARN)
    return
  end

  if not tmux_pane_exists(tmux_bottom_pane_id) then
    -- "-t" fijo al pane de Neovim: si el foco quedó en otro pane creado por
    -- ai_cli.lua, un split sin "-t" se intenta partir DENTRO de ese pane
    -- chico y falla en silencio.
    local out = vim.fn.system({
      "tmux", "split-window", "-v", "-l", "12",
      "-t", vim.env.TMUX_PANE,
      "-c", vim.fn.getcwd(), "-P", "-F", "#{pane_id}",
    })
    tmux_bottom_pane_id = vim.trim(out)
  else
    vim.fn.system({ "tmux", "select-pane", "-t", tmux_bottom_pane_id })
  end

  if cmd_opts.args ~= "" then
    vim.fn.system({ "tmux", "send-keys", "-t", tmux_bottom_pane_id, cmd_opts.args, "Enter" })
  end
end, { nargs = "*", desc = "Pane de tmux real abajo (opcional: comando a ejecutar)" })

-- :Sys -> monitor de recursos en una ventana flotante con la herramienta
-- disponible de mayor calidad visual y `top` como respaldo.
vim.api.nvim_create_user_command("Sys", function()
  local monitor = vim.fn.executable("btop") == 1 and "btop"
    or vim.fn.executable("htop") == 1 and "htop"
    or "top -o %CPU"
  local monitor_name = monitor == "btop" and "btop"
    or monitor == "htop" and "htop"
    or "top"
  local width = math.max(80, math.floor(vim.o.columns * 0.92))
  local height = math.max(20, math.floor(vim.o.lines * 0.86))
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = " Recursos del sistema · " .. monitor_name .. " · q para salir ",
    title_pos = "center",
    style = "minimal",
  })
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].cursorline = false
  vim.wo[win].winhighlight = "Normal:NormalFloat,NormalNC:NormalFloat,FloatBorder:FloatBorder"
  vim.bo[buf].bufhidden = "wipe"

  vim.fn.termopen(monitor, {
    on_exit = function()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end,
  })
  vim.cmd("startinsert")
  vim.keymap.set({ "n", "t" }, "q", "<cmd>q<CR>", { buffer = buf, desc = "Cerrar monitor" })
end, { desc = "Monitor de CPU/memoria a pantalla completa" })

vim.keymap.set("n", "<leader>ts", "<cmd>Sys<CR>", { desc = "System monitor (top)" })

vim.keymap.set("n", "<leader>tt", "<cmd>Term<CR>", { desc = "Terminal en pestaña" })

return {}
