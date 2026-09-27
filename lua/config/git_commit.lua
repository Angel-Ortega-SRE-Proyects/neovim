local M = {}

local function message_from_buffer(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local message = {}
  for _, line in ipairs(lines) do
    if not vim.startswith(vim.trim(line), "#") then message[#message + 1] = line end
  end
  return vim.trim(table.concat(message, "\n"))
end

function M.open(root, on_success, target_win, on_cancel)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "COMMIT_EDITMSG-" .. buf)
  vim.bo[buf].filetype = "gitcommit"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "",
    "# Escribe el mensaje del commit. Copilot puede sugerirlo aquí.",
    "# Tab acepta la sugerencia · Ctrl+] la descarta",
  })
  local win
  local previous_buf
  local previous_height
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    win = target_win
    previous_buf = vim.api.nvim_win_get_buf(win)
    previous_height = vim.api.nvim_win_get_height(win)
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
      title = " Mensaje del commit ",
      title_pos = "center",
    })
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].winhl = "Normal:NormalFloat,FloatBorder:FloatBorder"
  end
  vim.api.nvim_win_set_buf(win, buf)
  vim.cmd("startinsert")

  local function restore(cancelled)
    if vim.api.nvim_win_is_valid(win) then
      if type(previous_buf) == "number" and vim.api.nvim_buf_is_valid(previous_buf) then
        vim.api.nvim_win_set_buf(win, previous_buf)
        if previous_height then vim.api.nvim_win_set_height(win, previous_height) end
      else
        vim.api.nvim_win_close(win, true)
      end
    end
    if cancelled and on_cancel then on_cancel() end
  end

  vim.keymap.set("n", "q", function() restore(true) end, { buffer = buf, desc = "Cancelar commit" })
  vim.keymap.set("n", "<Esc>", function() restore(true) end, { buffer = buf, desc = "Cancelar commit" })

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
