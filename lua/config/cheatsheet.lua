-- Cheatsheet flotante persistente con TODOS los comandos y atajos custom,
-- generado dinámicamente (no una lista a mano que se desactualiza).
--
--   <leader>?   abre el cheatsheet
--   n / <Right> página siguiente
--   p / <Left>  página anterior
--   q / <Esc>   cerrar (no se cierra solo, ni con click afuera)
--
-- A diferencia de which-key (que muestra los <leader>-keymaps pero se cierra
-- al soltar la tecla y no lista comandos :Ex), esto junta keymaps + user
-- commands en un buffer normal que se queda abierto hasta que lo cierras vos.
local M = {}

local LINES_PER_PAGE = 22

local function collect_keymaps()
  local seen = {}
  local rows = {}
  for _, mode in ipairs({ "n", "v", "t" }) do
    for _, km in ipairs(vim.api.nvim_get_keymap(mode)) do
      if km.desc and (km.lhs:match("^<[Ll]eader>") or km.lhs:match("^<A%-")) then
        local key = mode .. km.lhs
        if not seen[key] then
          seen[key] = true
          table.insert(rows, { mode = mode, lhs = km.lhs, desc = km.desc })
        end
      end
    end
  end
  table.sort(rows, function(a, b) return a.lhs < b.lhs end)
  return rows
end

local function collect_commands()
  local rows = {}
  for name in pairs(vim.api.nvim_get_commands({ builtin = false })) do
    table.insert(rows, name)
  end
  table.sort(rows)
  return rows
end

local mode_label = { n = "normal", v = "visual", t = "terminal" }

local function build_lines()
  local lines = { "  COMANDOS (:Ex)", "" }
  for _, name in ipairs(collect_commands()) do
    table.insert(lines, string.format("  :%s", name))
  end

  table.insert(lines, "")
  table.insert(lines, "  ATAJOS (<leader>/<A-> con descripción)")
  table.insert(lines, "")
  for _, k in ipairs(collect_keymaps()) do
    table.insert(lines, string.format("  [%-8s] %-16s %s", mode_label[k.mode] or k.mode, k.lhs, k.desc))
  end

  return lines
end

local function paginate(lines)
  local pages = {}
  for i = 1, #lines, LINES_PER_PAGE do
    local page = {}
    for j = i, math.min(i + LINES_PER_PAGE - 1, #lines) do
      table.insert(page, lines[j])
    end
    table.insert(pages, page)
  end
  if #pages == 0 then
    pages = { { "  (sin comandos/atajos registrados todavía)" } }
  end
  return pages
end

local function open()
  local pages = paginate(build_lines())
  local page_idx = 1

  local width = math.floor(vim.o.columns * 0.6)
  local height = LINES_PER_PAGE + 2

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    style = "minimal",
  })

  local function render()
    vim.api.nvim_win_set_config(win, {
      title = string.format(" Cheatsheet (%d/%d) — q cierra, n/p página ", page_idx, #pages),
      title_pos = "center",
    })
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, pages[page_idx])
    vim.bo[buf].modifiable = false
  end

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function next_page()
    page_idx = page_idx % #pages + 1
    render()
  end

  local function prev_page()
    page_idx = (page_idx - 2) % #pages + 1
    render()
  end

  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "q", close, opts)
  vim.keymap.set("n", "<Esc>", close, opts)
  vim.keymap.set("n", "n", next_page, opts)
  vim.keymap.set("n", "<Right>", next_page, opts)
  vim.keymap.set("n", "p", prev_page, opts)
  vim.keymap.set("n", "<Left>", prev_page, opts)

  render()
end

function M.setup()
  vim.api.nvim_create_user_command("Cheatsheet", open, { desc = "Mostrar todos los comandos y atajos custom" })
  vim.keymap.set("n", "<leader>?", open, { desc = "Cheatsheet (todos los comandos/atajos)" })
end

return M
