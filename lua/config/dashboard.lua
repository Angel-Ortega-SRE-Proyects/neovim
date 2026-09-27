-- Vista de comandos disponibles: nombre + qué hace cada uno, agrupados por
-- categoría. Antes reemplazaba el buffer [No Name] inicial; ahora esa
-- pantalla de inicio la da snacks.nvim (ver lua/plugins/dashboard.lua) con
-- logo + botones estilo LazyVim, así que esto queda como :Commands para
-- consultarlo cuando quieras. Edita GROUPS para mantenerla al día.
local M = {}

local BUILTIN_COMMANDS = {
  { ":update", "Guardar el archivo actual" },
  { ":quit", "Cerrar la ventana actual" },
  { ":close", "Cerrar el split actual" },
  { ":split [archivo]", "Abrir split horizontal" },
  { ":vsplit [archivo]", "Abrir split vertical" },
  { ":NvimTreeFocus", "Enfocar el explorador" },
  { ":! comando", "Ejecutar un comando externo" },
  { ":help tema", "Consultar la ayuda de Vim/Neovim" },
}

local GROUPS = {
  {
    title = "Buscar (Telescope)",
    items = {
      { "<leader>ff", "Buscar archivos" },
      { "<C-f>", "Buscar y abrir archivos" },
      { "<leader>fg", "Buscar texto (live grep)" },
      { "<leader>fb", "Listar buffers abiertos" },
      { "<leader>fo", "Archivos recientes" },
      { "<leader>p  /  :Projects", "Carpetas recientes (Open Recent estilo VSCode)" },
    },
  },
  {
    title = "Git",
    items = {
      { "<leader>gc  /  :Gc", "Commits — Enter: ver diff del commit, C-o: checkout" },
      { "<leader>gs  /  :Gs", "Status — Enter: abrir archivo, C-d: ver diff" },
      { "<leader>gb  /  :Gb", "Listar branches" },
      { "<leader>gd  /  :DiffviewOpen", "Panel de diffs de lo cambiado" },
      { "<leader>gh  /  :DiffviewFileHistory %", "Historial del archivo actual" },
    },
  },
  {
    title = "Explorador de archivos",
    items = {
      { "<leader>e", "Mostrar/ocultar el explorador" },
      { ":NvimTreeFocus", "Enfocar el explorador" },
      { "C  (dentro del explorador)", "Cambiar cwd a la carpeta bajo el cursor" },
    },
  },
  {
    title = "Terminal",
    items = {
      { ":Term [comando]  /  <leader>tt", "Terminal como pestaña normal" },
      { ":Tf [comando]  /  <leader>tf  /  <C-\\>", "Terminal flotante" },
      { "nvim <carpeta/archivo>  (dentro de la terminal)", "Reutiliza este Neovim en vez de anidar otro" },
    },
  },
  {
    title = "Archivos y vistas",
    items = {
      { ":vsplit archivo", "Abrir archivo en vista vertical" },
      { ":split archivo", "Abrir archivo en vista horizontal" },
      { "Telescope + Ctrl-v", "Abrir selección en vista vertical" },
      { "Telescope + Ctrl-x", "Abrir selección en vista horizontal" },
      { "Telescope + Ctrl-t", "Abrir selección en pestaña" },
    },
  },
  {
    title = "Sistema",
    items = {
      { ":Sys  /  <leader>ts", "Monitor de CPU/memoria/disco (top)" },
      { "barra de estado", "CPU/MEM/DISK siempre visibles abajo" },
    },
  },
  {
    title = "LSP / código",
    items = {
      { "gd", "Ir a la definición" },
      { "gr", "Ver referencias" },
      { "K", "Documentación (hover)" },
      { "<leader>rn", "Renombrar símbolo" },
      { "<leader>d", "Ver diagnóstico en flotante" },
    },
  },
  {
    title = "Autocompletado / Copilot",
    items = {
      { "<Tab>", "Aceptar sugerencia (cmp o Copilot)" },
      { "<M-]> / <M-[>", "Copilot: siguiente / anterior sugerencia" },
      { "<C-]>", "Copilot: descartar sugerencia" },
      { ":Copilot auth", "Iniciar sesión en GitHub Copilot" },
    },
  },
  {
    title = "Edición general",
    items = {
      { ":update  /  :quit", "Guardar / salir" },
      { "<C-←/↓/↑/→>", "Moverse entre ventanas y panes" },
      { "<S-h> / <S-l>", "Buffer anterior / siguiente" },
    },
  },
}

local function compact(text, width)
  if #text <= width then
    return text
  end
  return text:sub(1, math.max(1, width - 1)) .. "…"
end

local function pad_right(text, width)
  return text .. string.rep(" ", math.max(0, width - #text))
end

local function append_columns(lines, title, items)
  local cell_width = math.max(28, math.floor((vim.o.columns - 10) / 2))
  table.insert(lines, "")
  table.insert(lines, "  " .. title)
  table.insert(lines, "  " .. string.rep("─", #title))
  for index = 1, #items, 2 do
    local left = pad_right(compact(items[index][1] .. "  " .. items[index][2], cell_width), cell_width)
    local right = items[index + 1]
      and compact(items[index + 1][1] .. "  " .. items[index + 1][2], cell_width)
      or ""
    table.insert(lines, "    " .. left .. "    " .. right)
  end
end

local function build_lines()
  local lines = {
    "  ÍNDICE DE COMANDOS Y ATAJOS",
    "  ══════════════════════════════════════════════════════════════",
  }

  for _, group in ipairs(GROUPS) do
    append_columns(lines, group.title, group.items)
  end

  append_columns(lines, "COMANDOS NATIVOS MÁS USADOS", BUILTIN_COMMANDS)

  local custom = vim.api.nvim_get_commands({ builtin = false })
  local names = vim.tbl_keys(custom)
  table.sort(names)
  local custom_items = {}
  for _, name in ipairs(names) do
    table.insert(custom_items, { ":" .. name, custom[name].desc or "" })
  end
  append_columns(lines, "COMANDOS DEL PROYECTO Y PLUGINS", custom_items)
  table.insert(lines, "")
  table.insert(lines, "  ↑/↓ mover · PageUp/PageDown desplazar · q/Esc cerrar · :command lista completa")

  return lines
end

local function open()
  local width = math.min(math.max(72, math.floor(vim.o.columns * 0.86)), vim.o.columns - 4)
  local height = math.min(math.max(20, math.floor(vim.o.lines * 0.78)), vim.o.lines - 4)
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = " Comandos y atajos ",
    title_pos = "center",
    style = "minimal",
  })
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "commandsdashboard"
  vim.wo[win].wrap = false
  vim.bo[buf].modifiable = true
  local ok, lines = pcall(build_lines)
  if not ok then
    lines = { "  No se pudo construir el índice de comandos.", "", "  " .. tostring(lines) }
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.wo[win].cursorline = true
  vim.wo[win].scrolloff = 5
  vim.wo[win].winhighlight = "Normal:NormalFloat,NormalNC:NormalFloat,FloatBorder:FloatBorder"
  vim.keymap.set("n", "q", "<cmd>bwipeout<CR>", { buffer = buf, silent = true, desc = "Cerrar índice" })
  vim.keymap.set("n", "<Esc>", "<cmd>bwipeout<CR>", { buffer = buf, silent = true, desc = "Cerrar índice" })
  vim.keymap.set("n", "<Up>", "k", { buffer = buf, noremap = true })
  vim.keymap.set("n", "<Down>", "j", { buffer = buf, noremap = true })
end

function M.setup()
  vim.api.nvim_create_user_command("Commands", open, { desc = "Ver comandos y atajos custom agrupados por categoría" })
  vim.keymap.set("c", "<CR>", function()
    if vim.fn.getcmdtype() == ":" and vim.fn.getcmdline() == "?" then
      return "<C-u>Commands<CR>"
    end
    return "<CR>"
  end, { expr = true, desc = "Abrir índice de comandos con :?" })
end

return M
