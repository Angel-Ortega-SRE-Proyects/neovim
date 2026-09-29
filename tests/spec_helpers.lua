-- Utilidades compartidas por los specs.
local M = {}

--- Escribe `lines` en `path`, creando las carpetas intermedias.
function M.write(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(type(lines) == "table" and lines or { lines }, path)
end

--- Codifica cada tabla como una línea JSON.
function M.jsonl(entries)
  return vim.tbl_map(vim.json.encode, entries)
end

--- Carpeta temporal nueva (se borra con M.cleanup()).
local temp_dirs = {}
function M.tempdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  table.insert(temp_dirs, dir)
  return vim.fn.resolve(dir)
end

function M.cleanup()
  for _, dir in ipairs(temp_dirs) do vim.fn.delete(dir, "rf") end
  temp_dirs = {}
end

--- Ejecuta git dentro de `root` y falla el test si el comando falla.
function M.git(root, args)
  local command = { "git", "-C", root }
  vim.list_extend(command, args)
  local output = vim.fn.system(command)
  assert(vim.v.shell_error == 0, table.concat(command, " ") .. "\n" .. output)
  return output
end

--- Repositorio Git temporal con un commit inicial.
function M.git_repo(files)
  local root = M.tempdir()
  M.git(root, { "init", "-q", "-b", "main" })
  for name, content in pairs(files or { ["README.md"] = "hola" }) do
    M.write(root .. "/" .. name, content)
  end
  M.git(root, { "add", "." })
  M.git(root, { "commit", "-q", "-m", "chore: inicio" })
  return root
end

--- Espera (procesando eventos) hasta que `predicate` sea verdadero.
function M.wait_for(predicate, timeout)
  return vim.wait(timeout or 3000, predicate, 20)
end

--- Deja una sola pestaña/ventana con un buffer vacío.
function M.reset_ui()
  pcall(vim.cmd, "stopinsert")
  pcall(vim.cmd, "silent! only!")
  while #vim.api.nvim_list_tabpages() > 1 do
    pcall(vim.cmd, "tabclose!")
  end
  pcall(vim.cmd, "silent! only!")
  vim.cmd("enew!")
end

--- Líneas del buffer.
function M.lines(buf)
  return vim.api.nvim_buf_get_lines(buf or 0, 0, -1, false)
end

--- Primera línea (1-indexada) que contiene `text` (búsqueda literal).
function M.find_line(buf, text)
  for index, line in ipairs(M.lines(buf)) do
    if line:find(text, 1, true) then return index end
  end
  return nil
end

--- Captura vim.notify durante `fn` y devuelve los mensajes.
function M.capture_notify(fn)
  local messages = {}
  local original = vim.notify
  vim.notify = function(msg, level) table.insert(messages, { msg = msg, level = level }) end
  local ok, err = pcall(fn)
  vim.notify = original
  assert(ok, err)
  return messages
end

--- Reemplaza temporalmente `tbl[key]` por `value` durante `fn`.
function M.stub(tbl, key, value, fn)
  local original = tbl[key]
  tbl[key] = value
  local ok, err = pcall(fn)
  tbl[key] = original
  assert(ok, err)
end

--- Ejecuta el mapping de buffer `lhs` en modo `mode` directamente.
function M.press(lhs, mode, buf)
  local map = vim.fn.maparg(lhs, mode or "n", false, true)
  if map.buffer ~= 1 and buf then
    for _, candidate in ipairs(vim.api.nvim_buf_get_keymap(buf, mode or "n")) do
      if candidate.lhs == lhs then map = candidate end
    end
  end
  assert(map and map.callback or map.rhs, "sin mapping para " .. lhs)
  if map.callback then
    return map.callback()
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(lhs, true, false, true), "x", false)
end

--- Crea en PATH un ejecutable falso `name` que duerme (para simular CLIs).
function M.fake_cli(bin_dir, name)
  local path = bin_dir .. "/" .. name
  M.write(path, { "#!/bin/sh", "exec sleep 600" })
  vim.fn.setfperm(path, "rwxr-xr-x")
  return path
end

return M
