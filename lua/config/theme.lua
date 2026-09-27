-- Selector de temas basado en los estilos oficiales de tokyonight, con una
-- capa de colores propia para que el fondo y la UI cambien con cada preset.
local previous = package.loaded["config.theme"]
local M = {}

M.colors = {
  bg = "#1c1c1c", -- carbón / dashboard
  bg_alt = "#262626", -- fondos secundarios (statusline, pmenu)
  fg = "#d4d4d4",
  green = "#a8b39b", -- acento oliva, sobrio
  green_bright = "#d2d9c7", -- destello / foco
  green_dim = "#7f8977", -- texto secundario, footer
  green_shade = "#303030", -- fondo de cursorline y selección suave
  selection = "#3d3d3d", -- selección visual
  brown = "#d19a66", -- acento secundario
  tan = "#e5c07b", -- descripciones, texto claro
  cyan = "#8abf7a", -- información activa y rutas
  diff_add_bg = "#19371e",
  diff_add_fg = "#a7d6a3",
  diff_delete_bg = "#4a2224",
  diff_delete_fg = "#e4a0a2",
  diff_change_bg = "#26362b",
  error = "#e49a9d",
  warn = "#e2b477",
}

M.palettes = {
  verde = vim.deepcopy(M.colors),
  ambar = {
    bg = "#24283b", bg_alt = "#1f2335", fg = "#c0caf5",
    green = "#e5a85c", green_bright = "#ffe0a3", green_dim = "#b58a52",
    green_shade = "#3a3024", selection = "#51402d", brown = "#ff9d5c",
    tan = "#ffd580", cyan = "#d7ba7d", diff_add_bg = "#26351f",
    diff_add_fg = "#b5e29a", diff_delete_bg = "#4a2525", diff_delete_fg = "#f0a0a0",
    diff_change_bg = "#3b3224", error = "#f08080", warn = "#ffbd69",
  },
  cian = {
    bg = "#222436", bg_alt = "#1e2030", fg = "#c8d3f5",
    green = "#63c7c2", green_bright = "#b7f4e9", green_dim = "#5f9e9c",
    green_shade = "#263d40", selection = "#31545a", brown = "#e3b56f",
    tan = "#f0d29a", cyan = "#70d6ff", diff_add_bg = "#1c3a35",
    diff_add_fg = "#9ee8c8", diff_delete_bg = "#48272d", diff_delete_fg = "#f0a3b0",
    diff_change_bg = "#263b40", error = "#f38ba8", warn = "#f5c47c",
  },
  violeta = {
    bg = "#e1e2e7", bg_alt = "#d0d5e3", fg = "#3760bf",
    green = "#c4a7e7", green_bright = "#eadcff", green_dim = "#9b88b8",
    green_shade = "#342d45", selection = "#4b3e63", brown = "#f6c177",
    tan = "#f9dcae", cyan = "#9ccfd8", diff_add_bg = "#24382f",
    diff_add_fg = "#a6daaa", diff_delete_bg = "#4b2934", diff_delete_fg = "#f2a6b3",
    diff_change_bg = "#383047", error = "#eb6f92", warn = "#f6c177",
  },
  carbon = {
    bg = "#1c1c1c", bg_alt = "#262626", fg = "#d4d4d4",
    green = "#b2b8aa", green_bright = "#e1e5d9", green_dim = "#838a7d",
    green_shade = "#303030", selection = "#3d3d3d", brown = "#c8aa7a",
    tan = "#d7c7a8", cyan = "#9aaeb0", diff_add_bg = "#243328",
    diff_add_fg = "#a9c9ad", diff_delete_bg = "#42282a", diff_delete_fg = "#dca5a6",
    diff_change_bg = "#34332b", error = "#e0a5a7", warn = "#d8b77c",
  },
  arena = {
    bg = "#262321", bg_alt = "#332e29", fg = "#e7dfd5",
    green = "#d0a46e", green_bright = "#f0d2a0", green_dim = "#9f805b",
    green_shade = "#40372f", selection = "#4b4035", brown = "#d28b62",
    tan = "#e4c69d", cyan = "#a8c3b5", diff_add_bg = "#29382f",
    diff_add_fg = "#b7d5b2", diff_delete_bg = "#482b2a", diff_delete_fg = "#e4aaa0",
    diff_change_bg = "#40382b", error = "#e39b91", warn = "#e3bd77",
  },
  pizarra = {
    bg = "#20242b", bg_alt = "#2b313b", fg = "#d7dde5",
    green = "#9bb4c8", green_bright = "#d2e1ec", green_dim = "#718595",
    green_shade = "#303944", selection = "#3b4653", brown = "#c9aa83",
    tan = "#d9c6a5", cyan = "#8fc6c5", diff_add_bg = "#243733",
    diff_add_fg = "#a9d1c0", diff_delete_bg = "#432b35", diff_delete_fg = "#dda8b6",
    diff_change_bg = "#303a40", error = "#e29aa8", warn = "#e0bd80",
  },
  ocaso = {
    bg = "#24212a", bg_alt = "#302b38", fg = "#e5dfea",
    green = "#c5a7c9", green_bright = "#eadcf0", green_dim = "#927e99",
    green_shade = "#3d3446", selection = "#4d4057", brown = "#d3aa82",
    tan = "#e2c9a9", cyan = "#9bb8c5", diff_add_bg = "#28372f",
    diff_add_fg = "#acd0b5", diff_delete_bg = "#482b3c", diff_delete_fg = "#e0a6bd",
    diff_change_bg = "#3b3342", error = "#e4a0b8", warn = "#dfbd80",
  },
}

-- Cada opción usa un estilo real de TokyoNight; la paleta custom ajusta la
-- superficie, acentos y grupos propios de esta configuración.
M.themes = {
  carbon = {
    scheme = "tokyonight-night", label = "Carbón", description = "oscuro neutro · #1c1c1c",
  },
  verde = {
    scheme = "tokyonight-night", label = "Verde suave", description = "oliva sobrio · noche",
  },
  ambar = {
    scheme = "tokyonight-storm", label = "Ámbar", description = "cálido · tormenta",
  },
  cian = {
    scheme = "tokyonight-moon", label = "Cian", description = "frío · luna",
  },
  ocaso = {
    scheme = "tokyonight-night", label = "Ocaso", description = "malva oscuro · tranquilo",
  },
  pizarra = {
    scheme = "tokyonight-moon", label = "Pizarra", description = "azul gris · sobrio",
  },
  arena = {
    scheme = "tokyonight-storm", label = "Arena", description = "tierra · cálido",
  },
  violeta = {
    scheme = "tokyonight-day", label = "Violeta", description = "claro · lavanda",
  },
}

-- Conserva la misma tabla al recargar init.lua: statusline y otros módulos
-- mantienen referencias a ella para actualizarse sin reiniciar Neovim.
if type(previous) == "table" and previous.colors then
  M.colors = previous.colors
end

local palette_file = vim.fn.stdpath("data") .. "/nvim-theme"

local function copy_palette(name)
  local selected = M.palettes[name]
  if not selected then
    return false
  end
  for key, value in pairs(selected) do
    M.colors[key] = value
  end
  M.active = name
  return true
end

local function load_saved_palette()
  local ok, saved = pcall(vim.fn.readfile, palette_file, "b")
  if not ok then
    saved = {}
  end
  local name = saved[1] and vim.trim(saved[1]) or "verde"
  copy_palette(name)
end

load_saved_palette()

-- Ajustes de superficie para que el preset también se refleje en ventanas,
-- menú, statusline y componentes que no siempre heredan el colorscheme.
function M.apply_base_highlights()
  local c = M.colors
  vim.api.nvim_set_hl(0, "Normal", { bg = c.bg, fg = c.fg })
  vim.api.nvim_set_hl(0, "NormalNC", { bg = c.bg, fg = c.fg })
  vim.api.nvim_set_hl(0, "NormalFloat", { bg = c.bg_alt, fg = c.fg })
  vim.api.nvim_set_hl(0, "FloatBorder", { bg = c.bg_alt, fg = c.green_dim })
  -- Grupo vim genérico (no de un plugin en particular) que tokyonight deja
  -- azul; bufferline.nvim lo usa para el título "Explorer" que aparece
  -- arriba del árbol (ver lua/plugins/editor.lua, offsets.highlight).
  vim.api.nvim_set_hl(0, "Directory", { fg = c.green, bold = true })
  vim.api.nvim_set_hl(0, "NvimTreeNormal", { bg = c.bg, fg = c.fg })
  vim.api.nvim_set_hl(0, "NvimTreeNormalNC", { bg = c.bg, fg = c.fg })
  vim.api.nvim_set_hl(0, "NvimTreeEndOfBuffer", { fg = c.bg })
  vim.api.nvim_set_hl(0, "NvimTreeWinSeparator", { bg = c.bg, fg = c.green_shade })
  vim.api.nvim_set_hl(0, "TabLine", { bg = c.bg, fg = c.green_dim })
  vim.api.nvim_set_hl(0, "TabLineFill", { bg = c.bg })
  vim.api.nvim_set_hl(0, "FloatTitle", { bg = c.bg_alt, fg = c.green_dim, bold = true })
  -- El menú de sugerencias de Noice conserva estos colores si aparece una
  -- ventana de selección al escribir comandos o rutas.
  vim.api.nvim_set_hl(0, "NoiceCmdlinePopupBorder", { fg = c.green_dim })
  vim.api.nvim_set_hl(0, "NoiceCmdlineIcon", { fg = c.brown })
  vim.api.nvim_set_hl(0, "NoicePopupmenu", { bg = c.bg_alt, fg = c.fg })
  vim.api.nvim_set_hl(0, "NoicePopupmenuBorder", { bg = c.bg_alt, fg = c.green })
  vim.api.nvim_set_hl(0, "NoicePopupmenuSelected", { bg = c.selection, fg = c.green_bright, bold = true })
  vim.api.nvim_set_hl(0, "NoicePopupmenuMatch", { fg = c.brown, bold = true })
  vim.api.nvim_set_hl(0, "NoiceNotify", { bg = c.bg_alt, fg = c.fg })
  vim.api.nvim_set_hl(0, "NoiceNotifyBorder", { bg = c.bg_alt, fg = c.warn, bold = true })
  -- Popup de which-key.nvim (se abre solo al tocar <leader>/g/etc.):
  -- tecla, grupo, descripción y separador venían en cian/violeta.
  vim.api.nvim_set_hl(0, "WhichKey", { fg = c.brown, bold = true })
  vim.api.nvim_set_hl(0, "WhichKeyGroup", { fg = c.green })
  vim.api.nvim_set_hl(0, "WhichKeyDesc", { fg = c.tan })
  vim.api.nvim_set_hl(0, "WhichKeySeparator", { fg = c.green_dim })
  vim.api.nvim_set_hl(0, "WhichKeyValue", { fg = c.green_dim })
  -- El fondo del popup no es "WhichKeyFloat" (no existe) sino
  -- "WhichKeyNormal" — which-key.nvim mapea winhighlight
  -- "Normal:WhichKeyNormal,FloatBorder:WhichKeyBorder,FloatTitle:WhichKeyTitle"
  -- (ver which-key/win.lua), por eso el override anterior no hacía nada.
  vim.api.nvim_set_hl(0, "WhichKeyNormal", { bg = c.bg_alt, fg = c.fg })
  vim.api.nvim_set_hl(0, "WinSeparator", { fg = c.green_shade })
  vim.api.nvim_set_hl(0, "StatusLine", { bg = c.bg_alt, fg = c.fg })
  vim.api.nvim_set_hl(0, "StatusLineNC", { bg = c.bg_alt, fg = c.green_dim })
  vim.api.nvim_set_hl(0, "CursorLine", { bg = c.green_shade })
  vim.api.nvim_set_hl(0, "CursorLineNr", { fg = c.green, bold = true })
  vim.api.nvim_set_hl(0, "LineNr", { fg = c.green_dim })
  vim.api.nvim_set_hl(0, "Visual", { bg = c.selection })
  vim.api.nvim_set_hl(0, "Search", { bg = c.brown, fg = c.bg })
  vim.api.nvim_set_hl(0, "TabLineSel", { bg = c.green, fg = c.bg, bold = true })
  vim.api.nvim_set_hl(0, "Pmenu", { bg = c.bg_alt, fg = c.fg })
  vim.api.nvim_set_hl(0, "PmenuSel", { bg = c.brown, fg = c.bg, bold = true })
  vim.api.nvim_set_hl(0, "DiffAdd", { bg = c.diff_add_bg, fg = c.diff_add_fg })
  vim.api.nvim_set_hl(0, "DiffDelete", { bg = c.diff_delete_bg, fg = c.diff_delete_fg })
  vim.api.nvim_set_hl(0, "DiffChange", { bg = c.diff_change_bg, fg = c.fg })
  vim.api.nvim_set_hl(0, "DiffText", { bg = c.green_shade, fg = c.green_bright, bold = true })
  vim.api.nvim_set_hl(0, "GitSignsAdd", { fg = c.diff_add_fg })
  vim.api.nvim_set_hl(0, "GitSignsChange", { fg = c.cyan })
  vim.api.nvim_set_hl(0, "GitSignsDelete", { fg = c.diff_delete_fg })
  vim.api.nvim_set_hl(0, "NonText", { fg = c.green_shade })
  vim.api.nvim_set_hl(0, "EndOfBuffer", { fg = c.green_shade })

  -- telescope.nvim: bordes/títulos venían en azul de tokyonight por
  -- defecto (ningún archivo los pisaba todavía) -- se ve en cualquier
  -- picker, incluido el de lua/plugins/ai_cli.lua (<leader>aa).
  vim.api.nvim_set_hl(0, "TelescopeNormal", { bg = c.bg_alt, fg = c.fg })
  vim.api.nvim_set_hl(0, "TelescopeBorder", { bg = c.bg_alt, fg = c.green_dim })
  vim.api.nvim_set_hl(0, "TelescopePromptNormal", { bg = c.bg_alt, fg = c.fg })
  vim.api.nvim_set_hl(0, "TelescopePromptBorder", { bg = c.bg_alt, fg = c.green_dim })
  vim.api.nvim_set_hl(0, "TelescopeResultsBorder", { bg = c.bg_alt, fg = c.green_dim })
  vim.api.nvim_set_hl(0, "TelescopePreviewBorder", { bg = c.bg_alt, fg = c.green_dim })
  vim.api.nvim_set_hl(0, "TelescopePromptTitle", { bg = c.green_shade, fg = c.green, bold = true })
  vim.api.nvim_set_hl(0, "TelescopeResultsTitle", { bg = c.green_shade, fg = c.green, bold = true })
  vim.api.nvim_set_hl(0, "TelescopePreviewTitle", { bg = c.green_shade, fg = c.green, bold = true })
  vim.api.nvim_set_hl(0, "TelescopeSelection", { bg = c.selection, fg = c.green_bright, bold = true })
  vim.api.nvim_set_hl(0, "TelescopeSelectionCaret", { bg = c.selection, fg = c.brown, bold = true })
  vim.api.nvim_set_hl(0, "TelescopeMatching", { fg = c.brown, bold = true })
  vim.api.nvim_set_hl(0, "TelescopePromptPrefix", { fg = c.green })

  vim.api.nvim_set_hl(0, "SpellBad", { sp = c.brown, undercurl = true })
end

function M.reload()
  local selected = M.themes[M.active] or M.themes.verde
  vim.cmd.colorscheme(selected.scheme)
  M.apply_base_highlights()
  vim.api.nvim_exec_autocmds("User", { pattern = "ThemeChanged" })
  vim.cmd("redraw!")
  vim.api.nvim_echo({
    { "Tema activo: ", "Normal" },
    { M.active or "verde", "String" },
  }, false, {})
end

local function theme_names()
  return { "carbon", "verde", "ambar", "cian", "ocaso", "pizarra", "arena", "violeta" }
end

local function save_theme(name)
  copy_palette(name)
  vim.fn.mkdir(vim.fn.stdpath("data"), "p")
  local ok, error_message = pcall(vim.fn.writefile, { name }, palette_file)
  if not ok then
    vim.notify("No se pudo guardar el tema: " .. error_message, vim.log.levels.WARN)
  end
  M.reload()
end

function M.select()
  local names = theme_names()
  local current = 1
  for index, name in ipairs(names) do
    if name == M.active then
      current = index
      break
    end
  end

  local width = math.min(math.max(58, math.floor(vim.o.columns * 0.58)), vim.o.columns - 4)
  local height = math.min(#names + 4, vim.o.lines - 4)
  local buffer = vim.api.nvim_create_buf(false, true)
  local window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2 - 1),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " Tema · elegir ",
    title_pos = "center",
  })

  local closed = false
  local function close()
    if closed then
      return
    end
    closed = true
    if vim.api.nvim_win_is_valid(window) then
      vim.api.nvim_win_close(window, true)
    end
    if vim.api.nvim_buf_is_valid(buffer) then
      vim.api.nvim_buf_delete(buffer, { force = true })
    end
  end

  local function render()
    local lines = {
      "  Temas disponibles",
      "  j/k o ↑/↓ · Enter aplicar · 1-8 elegir · q/Esc cancelar",
      "",
    }
    for index, name in ipairs(names) do
      local theme = M.themes[name]
      local marker = index == current and "●" or " "
      local active = name == M.active and "  activo" or ""
      lines[#lines + 1] = string.format(" %s %d  %-14s %-28s%s", marker, index, theme.label, theme.description, active)
    end
    vim.bo[buffer].modifiable = true
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.bo[buffer].modifiable = false
    if vim.api.nvim_win_is_valid(window) then
      vim.api.nvim_win_set_cursor(window, { current + 3, 0 })
    end
  end

  local function choose(index)
    if not names[index] then
      return
    end
    close()
    save_theme(names[index])
  end

  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.wo[window].cursorline = true
  vim.wo[window].wrap = false
  vim.wo[window].winhighlight = table.concat({
    "Normal:ThemePickerNormal",
    "NormalNC:ThemePickerNormal",
    "FloatBorder:ThemePickerBorder",
    "FloatTitle:ThemePickerTitle",
    "CursorLine:ThemePickerSelection",
  }, ",")

  local c = M.colors
  vim.api.nvim_set_hl(0, "ThemePickerNormal", { bg = "#1c1c1c", fg = c.fg })
  vim.api.nvim_set_hl(0, "ThemePickerBorder", { bg = "#1c1c1c", fg = c.green_dim })
  vim.api.nvim_set_hl(0, "ThemePickerTitle", { bg = "#1c1c1c", fg = c.tan, bold = true })
  vim.api.nvim_set_hl(0, "ThemePickerSelection", { bg = c.selection, fg = c.green_bright, bold = true })

  local opts = { buffer = buffer, nowait = true, silent = true }
  vim.keymap.set("n", "j", function()
    current = current % #names + 1
    render()
  end, opts)
  vim.keymap.set("n", "k", function()
    current = (current - 2) % #names + 1
    render()
  end, opts)
  vim.keymap.set("n", "<Down>", function()
    current = current % #names + 1
    render()
  end, opts)
  vim.keymap.set("n", "<Up>", function()
    current = (current - 2) % #names + 1
    render()
  end, opts)
  vim.keymap.set("n", "<CR>", function()
    choose(current)
  end, opts)
  vim.keymap.set("n", "q", close, opts)
  vim.keymap.set("n", "<Esc>", close, opts)
  for index = 1, #names do
    vim.keymap.set("n", tostring(index), function()
      choose(index)
    end, opts)
  end

  render()
end

vim.api.nvim_create_user_command("ThemeReload", M.reload, {
  desc = "Recargar la paleta del tema",
  force = true,
})
vim.api.nvim_create_user_command("ThemeSelect", M.select, {
  desc = "Seleccionar paleta de colores",
  force = true,
})

return M
