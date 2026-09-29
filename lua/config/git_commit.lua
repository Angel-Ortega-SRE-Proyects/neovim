local M = {}

local function repo_label(root)
  return vim.fn.fnamemodify(root, ":t")
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

local function trigger_copilot(buf, root)
  local ok, suggestion = pcall(require, "copilot.suggestion")
  if not ok then
    vim.notify("Copilot no está cargado. Ejecuta :Copilot status.", vim.log.levels.WARN)
    return
  end

  local command_ok, command = pcall(require, "copilot.command")
  if command_ok then
    pcall(command.attach, { bufnr = buf, force = true })
  end

  local attempts = { 0, 750, 2000, 4000, 7000 }
  local last_error
  local function request(index)
    if not vim.api.nvim_buf_is_valid(buf) then return end
    if vim.api.nvim_get_current_buf() ~= buf then
      local wins = vim.fn.win_findbuf(buf)
      if #wins > 0 and vim.api.nvim_win_is_valid(wins[1]) then
        vim.api.nvim_set_current_win(wins[1])
      end
    end
    if vim.fn.mode() ~= "i" then vim.cmd("startinsert") end
    local visible_ok, visible = pcall(suggestion.is_visible)
    if visible_ok and visible then return end
    local trigger_ok, trigger_error = pcall(suggestion.next)
    if not trigger_ok then last_error = trigger_error end
    if index < #attempts then
      vim.defer_fn(function() request(index + 1) end, attempts[index + 1] - attempts[index])
      return
    end
    local status = "sin respuesta"
    local status_ok, copilot_status = pcall(require, "config.copilot_status")
    if status_ok and copilot_status.message ~= "" then status = copilot_status.message end
    if last_error then status = tostring(last_error) end
    local attach_status = "desconocido"
    local client_ok, client = pcall(require, "copilot.client")
    local util_ok, util = pcall(require, "copilot.util")
    if client_ok and util_ok then
      local attached = client.buf_is_attached(buf) and "adjunto" or "no adjunto"
      attach_status = attached .. " · " .. util.get_buffer_attach_status(buf)
    end
    local fallback = fallback_commit_message(buf, root)
    vim.notify(
      "Copilot no generó una sugerencia: " .. status
        .. "\nBuffer: " .. attach_status
        .. "\nModo: " .. vim.fn.mode()
        .. "\nLog: " .. vim.fn.stdpath("log") .. "/copilot-lua.log"
        .. (fallback and "\nSe insertó una propuesta local: " .. fallback or ""),
      vim.log.levels.WARN
    )
  end
  vim.defer_fn(function() request(1) end, attempts[1])
end

local function request_copilot_message(buf, root)
  local staged_diff = vim.fn.systemlist({ "git", "-C", root, "diff", "--cached" })
  local staged_ok = vim.v.shell_error == 0 and #staged_diff > 0
  local diff_lines = staged_ok and staged_diff or vim.fn.systemlist({ "git", "-C", root, "diff" })
  if vim.v.shell_error ~= 0 or #diff_lines == 0 then
    vim.notify("No hay cambios para describir", vim.log.levels.WARN)
    return
  end
  if vim.b[buf].copilot_commit_prompt then
    trigger_copilot(buf, root)
    return
  end
  vim.b[buf].copilot_commit_prompt = true
  local prompt = {
    "# Repositorio: " .. repo_label(root),
    "# Ruta: " .. vim.fn.fnamemodify(root, ":~"),
    staged_ok
      and "# Copilot: genera un mensaje Conventional Commit breve basado en el diff completo (staged) de abajo."
      or "# Copilot: genera un mensaje Conventional Commit breve basado en el diff completo de abajo.",
    "# Usa el formato tipo(scope): descripción y no agregues explicaciones.",
    staged_ok and "# Hay cambios staged listos para commit." or "# Aviso: estos cambios aún no están staged; agrégalos antes de guardar.",
    string.format("# --- diff completo (%d líneas) ---", #diff_lines),
  }
  local MAX_DIFF_LINES = 400
  local truncated = #diff_lines > MAX_DIFF_LINES
  local shown_diff = truncated and vim.list_slice(diff_lines, 1, MAX_DIFF_LINES) or diff_lines
  for _, line in ipairs(shown_diff) do
    prompt[#prompt + 1] = "# " .. line
  end
  if truncated then
    prompt[#prompt + 1] = string.format(
      "# ... diff truncado (%d de %d líneas) para no saturar el contexto de Copilot ...",
      MAX_DIFF_LINES, #diff_lines
    )
  end
  prompt[#prompt + 1] = "# --- fin del diff ---"
  prompt[#prompt + 1] = "# Escribe únicamente el mensaje del commit en la línea siguiente."
  prompt[#prompt + 1] = ""
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, prompt)
  vim.api.nvim_win_set_cursor(0, { #prompt, 0 })
  vim.cmd("startinsert")
  trigger_copilot(buf, root)
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
    "# Ctrl-G genera con Copilot · Tab acepta · Ctrl-] descarta",
    "# Escribe el mensaje manualmente o solicita una sugerencia.",
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
  end
  vim.api.nvim_win_set_buf(win, buf)
  -- Después de set_buf: al cambiar de buffer Neovim restaura las opciones
  -- locales de ventana guardadas para ese buffer y pisaría estos valores.
  if previous_buf then
    vim.wo[win].winbar = " COMMIT · " .. repo_label(root) .. " · Copilot "
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

  vim.keymap.set("n", "q", function() restore(true) end, { buffer = buf, desc = "Cancelar commit" })
  vim.keymap.set("n", "<Esc>", function() restore(true) end, { buffer = buf, desc = "Cancelar commit" })
  vim.keymap.set({ "n", "i" }, "<C-g>", function()
    request_copilot_message(buf, root)
  end, { buffer = buf, desc = "Generar mensaje de commit con Copilot", silent = true })

  request_copilot_message(buf, root)

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local message = message_from_buffer(buf)
      if message == "" then
        vim.notify("El commit necesita un mensaje", vim.log.levels.WARN)
        return
      end
      vim.system({ "git", "-C", root, "commit", "-F", "-" },
        { text = true, stdin = message }, function(result)
          vim.schedule(function()
            if result.code ~= 0 then
              vim.notify(vim.trim(result.stderr or "No se pudo crear el commit"), vim.log.levels.ERROR)
              return
            end
            restore(false)
            if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
            vim.notify("Commit creado", vim.log.levels.INFO)
            if on_success then on_success() end
          end)
        end)
    end,
  })
end

return M
