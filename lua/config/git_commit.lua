local M = {}
local i18n = require("config.i18n")

local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinners = {}

local function repo_label(root)
  return vim.fn.fnamemodify(root, ":t")
end

-- El ghost-text de copilot.lua (suggestion.next(), endpoint "getCompletions")
-- devuelve consistentemente `completions = {}` para el filetype `gitcommit`
-- (languageId normalizado a "git-commit") -- reproducido en aislamiento:
-- cliente ya autenticado y "Normal", diff chico, cursor en la mejor
-- posición posible, y aun así respuesta vacía en <10ms. Confirmado además
-- que en archivos de código normales sí sugiere -- no es config nuestra,
-- es que ese endpoint está pensado para continuar código, no para generar
-- prosa desde cero. Por eso usamos CopilotChat.nvim (endpoint de chat,
-- diseñado justamente para esto) en su lugar -- ver plugins/copilot_chat.lua.
local warmed = false
function M.warm()
  if warmed then return end
  local ok_lazy, lazy = pcall(require, "lazy")
  if ok_lazy then pcall(lazy.load, { plugins = { "copilot.lua", "CopilotChat.nvim" } }) end
  warmed = true
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

local function build_chat_prompt(root, staged_ok, diff_lines)
  local rules = {
    i18n.t("Genera un mensaje de commit siguiendo estas reglas y el diff de abajo. Responde ÚNICAMENTE con el mensaje del commit, sin explicaciones ni bloques de código."),
    i18n.t("Título (línea 1): tipo(scope): descripción corta en imperativo, sin punto final."),
    i18n.t("  Tipo: usa 'feat' SOLO si el diff agrega funcionalidad nueva. Para todo lo demás"),
    i18n.t("  (correcciones, ajustes de comportamiento, refactor, estilo, docs, tests, tareas"),
    i18n.t("  de mantenimiento) usa 'fix', 'refactor', 'style', 'docs', 'test' o 'chore' según"),
    i18n.t("  corresponda -- nunca 'feat' para un ajuste."),
    i18n.t("  Scope: nombre corto del módulo/área principal tocada por el diff."),
    i18n.t("Cuerpo: deja una línea en blanco tras el título. Si el diff mezcla features nuevas"),
    i18n.t("  con ajustes/correcciones, agrega dos listas con viñetas '-':"),
    "  " .. i18n.t("Features:"),
    "  - ...",
    "  " .. i18n.t("Ajustes:"),
    "  - ...",
    i18n.t("  Si el diff es solo de un tipo, incluí solo esa lista (o ninguna si el título ya"),
    i18n.t("  describe todo el cambio). No inventes cambios que no estén en el diff."),
    "",
    i18n.t("Repositorio:") .. " " .. repo_label(root),
    (staged_ok and i18n.t("Hay cambios staged listos para commit.") or i18n.t("Aviso: estos cambios aún no están staged; agrégalos antes de guardar.")),
    "",
  }
  vim.list_extend(rules, diff_lines)
  return table.concat(rules, "\n")
end

local function sanitize_chat_response(text)
  text = vim.trim(text or "")
  -- Algunos modelos envuelven la respuesta en un bloque de código pese a
  -- que se les pidió que no lo hagan -- quitarlo si aparece.
  text = text:gsub("^```[%w_-]*\n?", ""):gsub("\n?```$", "")
  return vim.trim(text)
end

local function insert_chat_message(buf, message)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local msg_lines = vim.split(message, "\n", { plain = true })
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local insert_at = 0
  for index, line in ipairs(lines) do
    if vim.trim(line) == "" then
      insert_at = index - 1
      break
    end
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, insert_at, insert_at + 1, false, msg_lines)
  local last_line = insert_at + #msg_lines
  vim.api.nvim_win_set_cursor(0, { last_line, #msg_lines[#msg_lines] })
end

local function request_copilot_message(buf, root, win)
  local staged_diff = vim.fn.systemlist({ "git", "-C", root, "diff", "--cached" })
  local staged_ok = vim.v.shell_error == 0 and #staged_diff > 0
  local diff_lines = staged_ok and staged_diff or vim.fn.systemlist({ "git", "-C", root, "diff" })
  if vim.v.shell_error ~= 0 or #diff_lines == 0 then
    vim.notify(i18n.t("No hay cambios para describir"), vim.log.levels.WARN)
    return
  end

  local ok_chat, chat = pcall(require, "CopilotChat")
  if not ok_chat then
    vim.notify(i18n.t("CopilotChat no está instalado o no cargó. Revisa lua/plugins/copilot_chat.lua."), vim.log.levels.WARN)
    return
  end

  local MAX_DIFF_LINES = 800
  local truncated = #diff_lines > MAX_DIFF_LINES
  local shown_diff = truncated and vim.list_slice(diff_lines, 1, MAX_DIFF_LINES) or diff_lines
  local prompt = build_chat_prompt(root, staged_ok, shown_diff)

  start_copilot_spinner(buf, win, root)
  local answered = false

  local function finish(message, notify_text)
    if answered then return end
    answered = true
    if not vim.api.nvim_buf_is_valid(buf) then return end
    if message and message ~= "" then
      insert_chat_message(buf, message)
      stop_copilot_spinner(buf, win, " COMMIT · " .. repo_label(root) .. " · " .. i18n.t("mensaje generado") .. " ")
    else
      local fallback = fallback_commit_message(buf, root)
      stop_copilot_spinner(buf, win, " COMMIT · " .. repo_label(root) .. " · " .. i18n.t("Copilot sin respuesta, revisa con Ctrl-G") .. " ")
      vim.notify(
        (notify_text or i18n.t("Copilot Chat no devolvió una respuesta"))
          .. (fallback and (i18n.t("\nSe insertó una propuesta local: ") .. fallback) or ""),
        vim.log.levels.WARN
      )
    end
  end

  -- Salvavidas: si CopilotChat nunca llama al callback (error interno
  -- silencioso, cancelación, etc.), no dejar el spinner girando para siempre.
  vim.defer_fn(function() finish(nil) end, 25000)

  local ask_ok, ask_err = pcall(chat.ask, prompt, {
    headless = true,
    callback = vim.schedule_wrap(function(response)
      local content = response and sanitize_chat_response(response.content)
      finish(content ~= "" and content or nil)
    end),
  })
  if not ask_ok then
    finish(nil, tostring(ask_err))
  end
end

function M.open(root, on_success, target_win, on_cancel)
  local buf = vim.api.nvim_create_buf(true, false)
  local staged = vim.fn.systemlist({ "git", "-C", root, "diff", "--cached" })
  local staged_ok = vim.v.shell_error == 0 and #staged > 0
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = true
  vim.api.nvim_buf_set_name(buf, "COMMIT_EDITMSG-" .. buf)
  vim.bo[buf].filetype = "gitcommit"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "# " .. i18n.t("Repositorio:") .. " " .. repo_label(root),
    "# " .. i18n.t("Ruta:") .. " " .. vim.fn.fnamemodify(root, ":~"),
    "# " .. (staged_ok and i18n.t("Hay cambios staged listos para commit")
      or i18n.t("Aviso: estos cambios aún no están staged")),
    "",
    "# " .. i18n.t("Ctrl-G genera con Copilot Chat · q/Esc cancela"),
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
      local function commit()
        vim.system({ "git", "-C", root, "commit", "-F", "-" },
          { text = true, stdin = message }, function(result)
            vim.schedule(function()
              if result.code ~= 0 then
                -- git escribe "nothing to commit" / "no changes added" en
                -- stdout, no en stderr: mostrar el que tenga contenido.
                local detail = vim.trim(result.stderr or "")
                if detail == "" then detail = vim.trim(result.stdout or "") end
                vim.notify(detail ~= "" and detail or i18n.t("No se pudo crear el commit"), vim.log.levels.ERROR)
                return
              end
              restore(false)
              if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
              vim.notify(i18n.t("Commit creado"), vim.log.levels.INFO)
              if on_success then on_success() end
            end)
          end)
      end

      -- `git commit` falla si no hay nada en staging. Se ofrece prepararlo
      -- todo en vez de obligar a salir del flujo (git add -A es reversible
      -- con git reset).
      local staged = vim.system({ "git", "-C", root, "diff", "--cached", "--quiet" }):wait()
      if staged.code == 0 then
        vim.ui.select({ i18n.t("Preparar todo (git add -A) y commitear"), i18n.t("Cancelar") }, {
          prompt = i18n.t("No hay cambios en staging"),
        }, function(_, index)
          if index ~= 1 then return end
          local added = vim.system({ "git", "-C", root, "add", "-A" }, { text = true }):wait()
          if added.code ~= 0 then
            vim.notify(vim.trim(added.stderr or ""), vim.log.levels.ERROR)
            return
          end
          commit()
        end)
        return
      end
      commit()
    end,
  })
end

return M
