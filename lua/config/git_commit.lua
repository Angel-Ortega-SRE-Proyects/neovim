local M = {}
local i18n = require("config.i18n")

local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinners = {}

local function repo_label(root)
  return vim.fn.fnamemodify(root, ":t")
end

-- copilot.lua carga (event = "InsertEnter" en plugins/copilot.lua) recién
-- la primera vez que se entra a modo inserción en la sesión -- si esa
-- primera vez es exactamente cuando abrimos el buffer de commit, el
-- cliente LSP arranca y autentica EN ESE MOMENTO (cold start de varios
-- segundos) justo cuando más necesitamos una respuesta rápida
-- (confirmado en copilot-lua.log: primera respuesta ~4ms con
-- completions={}, seguida 3-4s después de un "finish reason: stop" que
-- ya no llega a tiempo). M.warm() fuerza ese arranque antes -- se llama
-- al abrir el menú Git Hub o el panel de cambios, dándole al cliente
-- varios segundos de margen mientras el usuario todavía está navegando.
local warmed = false
function M.warm()
  if warmed then return end
  local ok_lazy, lazy = pcall(require, "lazy")
  if ok_lazy then pcall(lazy.load, { plugins = { "copilot.lua" } }) end
  local ok_command, command = pcall(require, "copilot.command")
  if not ok_command then return end
  warmed = true
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "gitcommit"
  pcall(command.attach, { bufnr = buf, force = true })
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
  end, 15000)
end

local function idle_winbar(root)
  return " COMMIT · " .. repo_label(root) .. " · Copilot "
end

local function set_winbar(win, text)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.wo[win].winbar = text
  end
end

local function stop_copilot_spinner(buf, win, idle_text)
  local spinner = spinners[buf]
  if spinner then
    spinner.timer:stop()
    spinner.timer:close()
    spinners[buf] = nil
  end
  if idle_text then set_winbar(win, idle_text) end
end

local function start_copilot_spinner(buf, win, root)
  stop_copilot_spinner(buf, win)
  local frame = 0
  local timer = vim.uv.new_timer()
  spinners[buf] = { timer = timer }
  timer:start(0, 120, vim.schedule_wrap(function()
    if not vim.api.nvim_buf_is_valid(buf) or not (win and vim.api.nvim_win_is_valid(win)) then
      stop_copilot_spinner(buf, win)
      return
    end
    frame = (frame % #SPINNER_FRAMES) + 1
    set_winbar(win, string.format(" %s " .. i18n.t("Generando mensaje con Copilot · %s") .. " ",
      SPINNER_FRAMES[frame], repo_label(root)))
  end))
end

local function message_from_buffer(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local message = {}
  for _, line in ipairs(lines) do
    if not vim.startswith(vim.trim(line), "#") then message[#message + 1] = line end
  end
  return vim.trim(table.concat(message, "\n"))
end

local function resize_commit_window(win)
  if not vim.api.nvim_win_is_valid(win) then return end
  local config = vim.api.nvim_win_get_config(win)
  if config.relative == "" then return end
  local width = math.min(90, math.max(58, vim.o.columns - 10))
  local height = math.min(10, math.max(6, vim.o.lines - 8))
  config.width = width
  config.height = height
  config.row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
  config.col = math.max(0, math.floor((vim.o.columns - width) / 2))
  pcall(vim.api.nvim_win_set_config, win, config)
end

local function fallback_commit_message(buf, root)
  local files = vim.fn.systemlist({ "git", "-C", root, "diff", "--name-only" })
  if #files == 0 then
    files = vim.fn.systemlist({ "git", "-C", root, "diff", "--cached", "--name-only" })
  end
  local scope = vim.fn.fnamemodify(root, ":t"):gsub("[^%w%-]", "-")
  local message = string.format("chore(%s): update project changes", scope)
  local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for index, line in ipairs(current) do
    if vim.trim(line) == "" then
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, index - 1, index, false, { message })
      vim.bo[buf].modifiable = true
      vim.api.nvim_win_set_cursor(0, { index, 0 })
      return message
    end
  end
  return nil
end

local function trigger_copilot(buf, root, win)
  local ok, suggestion = pcall(require, "copilot.suggestion")
  if not ok then
    vim.notify(i18n.t("Copilot no está cargado. Ejecuta :Copilot status."), vim.log.levels.WARN)
    return
  end

  local command_ok, command = pcall(require, "copilot.command")
  if command_ok then
    pcall(command.attach, { bufnr = buf, force = true })
  end

  start_copilot_spinner(buf, win, root)

  local attempts = { 0, 750, 2000, 4000, 7000, 10000 }
  local last_error
  local function request(index)
    if not vim.api.nvim_buf_is_valid(buf) then
      stop_copilot_spinner(buf, win)
      return
    end
    if vim.api.nvim_get_current_buf() ~= buf then
      local wins = vim.fn.win_findbuf(buf)
      if #wins > 0 and vim.api.nvim_win_is_valid(wins[1]) then
        vim.api.nvim_set_current_win(wins[1])
      end
    end
    if vim.fn.mode() ~= "i" then vim.cmd("startinsert") end
    local visible_ok, visible = pcall(suggestion.is_visible)
    if visible_ok and visible then
      stop_copilot_spinner(buf, win, " COMMIT · " .. repo_label(root) .. " · " .. i18n.t("sugerencia lista, Tab para aceptar") .. " ")
      return
    end
    local trigger_ok, trigger_error = pcall(suggestion.next)
    if not trigger_ok then last_error = trigger_error end
    if index < #attempts then
      vim.defer_fn(function() request(index + 1) end, attempts[index + 1] - attempts[index])
      return
    end
    local status = i18n.t("sin respuesta")
    local status_ok, copilot_status = pcall(require, "config.copilot_status")
    if status_ok and copilot_status.message ~= "" then status = copilot_status.message end
    if last_error then status = tostring(last_error) end
    local attach_status = i18n.t("desconocido")
    local client_ok, client = pcall(require, "copilot.client")
    local util_ok, util = pcall(require, "copilot.util")
    if client_ok and util_ok then
      local attached = client.buf_is_attached(buf) and i18n.t("adjunto") or i18n.t("no adjunto")
      attach_status = attached .. " · " .. util.get_buffer_attach_status(buf)
    end
    local fallback = fallback_commit_message(buf, root)
    stop_copilot_spinner(buf, win, " COMMIT · " .. repo_label(root) .. " · " .. i18n.t("Copilot sin respuesta, revisa con Ctrl-G") .. " ")
    vim.notify(
      i18n.t("Copilot no generó una sugerencia: ") .. status
        .. i18n.t("\nBuffer: ") .. attach_status
        .. i18n.t("\nModo: ") .. vim.fn.mode()
        .. i18n.t("\nLog: ") .. vim.fn.stdpath("log") .. "/copilot-lua.log"
        .. (fallback and (i18n.t("\nSe insertó una propuesta local: ") .. fallback) or ""),
      vim.log.levels.WARN
    )
  end
  vim.defer_fn(function() request(1) end, attempts[1])
end

local function request_copilot_message(buf, root, win)
  local staged_diff = vim.fn.systemlist({ "git", "-C", root, "diff", "--cached" })
  local staged_ok = vim.v.shell_error == 0 and #staged_diff > 0
  local diff_lines = staged_ok and staged_diff or vim.fn.systemlist({ "git", "-C", root, "diff" })
  if vim.v.shell_error ~= 0 or #diff_lines == 0 then
    vim.notify(i18n.t("No hay cambios para describir"), vim.log.levels.WARN)
    return
  end
  if vim.b[buf].copilot_commit_prompt then
    trigger_copilot(buf, root, win)
    return
  end
  vim.b[buf].copilot_commit_prompt = true

  -- El mensaje va PRIMERO (cursor en línea 1) y el diff al final, como
  -- hace `git commit -v` -- con el diff completo arriba, el cursor
  -- quedaba al fondo de un muro de ~400 líneas de comentarios sin nada
  -- después, y Copilot respondía con completions vacías en esa posición
  -- (confirmado en copilot-lua.log: respuesta rápida, 0 sugerencias).
  local lines = {
    "",
    "# " .. i18n.t("Repositorio:") .. " " .. repo_label(root),
    "# " .. i18n.t("Ruta:") .. " " .. vim.fn.fnamemodify(root, ":~"),
    "# " .. (staged_ok
      and i18n.t("Copilot: analiza el diff completo (staged) de abajo y genera un commit Conventional Commits.")
      or i18n.t("Copilot: analiza el diff completo de abajo y genera un commit Conventional Commits.")),
    "# " .. i18n.t("Título (línea 1): tipo(scope): descripción corta en imperativo, sin punto final."),
    "# " .. i18n.t("  Tipo: usa 'feat' SOLO si el diff agrega funcionalidad nueva. Para todo lo demás"),
    "# " .. i18n.t("  (correcciones, ajustes de comportamiento, refactor, estilo, docs, tests, tareas"),
    "# " .. i18n.t("  de mantenimiento) usa 'fix', 'refactor', 'style', 'docs', 'test' o 'chore' según"),
    "# " .. i18n.t("  corresponda -- nunca 'feat' para un ajuste."),
    "# " .. i18n.t("  Scope: nombre corto del módulo/área principal tocada por el diff."),
    "# " .. i18n.t("Cuerpo: deja una línea en blanco tras el título. Si el diff mezcla features nuevas"),
    "# " .. i18n.t("  con ajustes/correcciones, agrega dos listas con viñetas '-':"),
    "#     " .. i18n.t("Features:"),
    "#     - ...",
    "#     " .. i18n.t("Ajustes:"),
    "#     - ...",
    "# " .. i18n.t("  Si el diff es solo de un tipo, incluí solo esa lista (o ninguna si el título ya"),
    "# " .. i18n.t("  describe todo el cambio). No inventes cambios que no estén en el diff."),
    "# " .. (staged_ok and i18n.t("Hay cambios staged listos para commit.") or i18n.t("Aviso: estos cambios aún no están staged; agrégalos antes de guardar.")),
    "# " .. i18n.t("Ctrl-G genera con Copilot · Tab acepta · Ctrl-] descarta"),
    "# " .. i18n.t("Escribe el mensaje manualmente o solicita una sugerencia."),
    "# " .. string.format(i18n.t("--- diff completo (%d líneas) ---"), #diff_lines),
  }
  local MAX_DIFF_LINES = 400
  local truncated = #diff_lines > MAX_DIFF_LINES
  local shown_diff = truncated and vim.list_slice(diff_lines, 1, MAX_DIFF_LINES) or diff_lines
  for _, line in ipairs(shown_diff) do
    lines[#lines + 1] = "# " .. line
  end
  if truncated then
    lines[#lines + 1] = "# " .. string.format(
      i18n.t("... diff truncado (%d de %d líneas) para no saturar el contexto de Copilot ..."),
      MAX_DIFF_LINES, #diff_lines
    )
  end
  lines[#lines + 1] = "# " .. i18n.t("--- fin del diff ---")

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd("startinsert")
  trigger_copilot(buf, root, win)
end

function M.open(root, on_success, target_win, on_cancel)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = true
  vim.api.nvim_buf_set_name(buf, "COMMIT_EDITMSG-" .. buf)
  vim.bo[buf].filetype = "gitcommit"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "",
    "# " .. i18n.t("Ctrl-G genera con Copilot · Tab acepta · Ctrl-] descarta"),
    "# " .. i18n.t("Escribe el mensaje manualmente o solicita una sugerencia."),
  })
  local win
  local previous_buf
  local previous_height
  local previous_winbar
  local previous_wrap
  local previous_linebreak
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    win = target_win
    previous_buf = vim.api.nvim_win_get_buf(win)
    previous_height = vim.api.nvim_win_get_height(win)
    previous_winbar = vim.wo[win].winbar
    previous_wrap = vim.wo[win].wrap
    previous_linebreak = vim.wo[win].linebreak
    vim.api.nvim_win_set_height(win, math.max(6, previous_height))
  else
    local width = math.min(90, math.max(58, vim.o.columns - 10))
    local height = 8
    win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
      col = math.max(0, math.floor((vim.o.columns - width) / 2)),
      width = width,
      height = height,
      style = "minimal",
      border = "rounded",
      title = " Commit · " .. repo_label(root) .. " ",
      title_pos = "center",
    })
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].winhl = "Normal:NormalFloat,FloatBorder:FloatBorder"
    vim.wo[win].winbar = idle_winbar(root)
  end
  vim.api.nvim_win_set_buf(win, buf)
  -- Después de set_buf: al cambiar de buffer Neovim restaura las opciones
  -- locales de ventana guardadas para ese buffer y pisaría estos valores.
  if previous_buf then
    vim.wo[win].winbar = idle_winbar(root)
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
  end
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    buffer = buf,
    callback = function()
      resize_commit_window(win)
    end,
  })
  vim.cmd("startinsert")

  local function restore(cancelled)
    stop_copilot_spinner(buf, win)
    if vim.api.nvim_win_is_valid(win) then
      vim.bo[buf].modified = false
      if type(previous_buf) == "number" and vim.api.nvim_buf_is_valid(previous_buf) then
        vim.api.nvim_win_set_buf(win, previous_buf)
        if previous_height then vim.api.nvim_win_set_height(win, previous_height) end
        vim.wo[win].winbar = previous_winbar or ""
        vim.wo[win].wrap = previous_wrap
        vim.wo[win].linebreak = previous_linebreak
      else
        vim.api.nvim_win_close(win, true)
      end
    end
    if cancelled and on_cancel then on_cancel() end
  end

  vim.keymap.set("n", "q", function() restore(true) end, { buffer = buf, desc = i18n.t("Cancelar commit") })
  vim.keymap.set("n", "<Esc>", function() restore(true) end, { buffer = buf, desc = i18n.t("Cancelar commit") })
  vim.keymap.set({ "n", "i" }, "<C-g>", function()
    request_copilot_message(buf, root, win)
  end, { buffer = buf, desc = i18n.t("Generar mensaje de commit con Copilot"), silent = true })

  request_copilot_message(buf, root, win)

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local message = message_from_buffer(buf)
      if message == "" then
        vim.notify(i18n.t("El commit necesita un mensaje"), vim.log.levels.WARN)
        return
      end
      vim.system({ "git", "-C", root, "commit", "-F", "-" },
        { text = true, stdin = message }, function(result)
          vim.schedule(function()
            if result.code ~= 0 then
              vim.notify(vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr) or i18n.t("No se pudo crear el commit"), vim.log.levels.ERROR)
              return
            end
            restore(false)
            if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
            vim.notify(i18n.t("Commit creado"), vim.log.levels.INFO)
            if on_success then on_success() end
          end)
        end)
    end,
  })
end

return M
