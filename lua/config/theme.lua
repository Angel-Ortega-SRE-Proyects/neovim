-- Paleta única (verde / café / negro) para reemplazar los acentos
-- azul/violeta por defecto de tokyonight en toda la UI custom del config
-- (dashboard, explorador, statusline, etc.). Todos esos archivos importan
-- esta tabla en vez de hardcodear sus propios hex, así un cambio de color
-- acá se propaga a todo el editor de una.
local previous = package.loaded["config.theme"]
local M = {}

M.colors = {
  bg = "#1c1c1c",
  bg_alt = "#262626", -- fondos secundarios (statusline, pmenu)
  fg = "#d4d4d4",
  green = "#98c379", -- acento principal
  green_bright = "#c8e6b0", -- destello / foco
  green_dim = "#789568", -- texto secundario, footer
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
    bg = "#1c1c1c", bg_alt = "#29231c", fg = "#e6e1d5",
    green = "#e5a85c", green_bright = "#ffe0a3", green_dim = "#b58a52",
    green_shade = "#3a3024", selection = "#51402d", brown = "#ff9d5c",
    tan = "#ffd580", cyan = "#d7ba7d", diff_add_bg = "#26351f",
    diff_add_fg = "#b5e29a", diff_delete_bg = "#4a2525", diff_delete_fg = "#f0a0a0",
    diff_change_bg = "#3b3224", error = "#f08080", warn = "#ffbd69",
  },
  cian = {
    bg = "#171d20", bg_alt = "#202b30", fg = "#d7e5e7",
    green = "#63c7c2", green_bright = "#b7f4e9", green_dim = "#5f9e9c",
    green_shade = "#263d40", selection = "#31545a", brown = "#e3b56f",
    tan = "#f0d29a", cyan = "#70d6ff", diff_add_bg = "#1c3a35",
    diff_add_fg = "#9ee8c8", diff_delete_bg = "#48272d", diff_delete_fg = "#f0a3b0",
    diff_change_bg = "#263b40", error = "#f38ba8", warn = "#f5c47c",
  },
  violeta = {
    bg = "#1d1b24", bg_alt = "#292533", fg = "#e3dff0",
    green = "#c4a7e7", green_bright = "#eadcff", green_dim = "#9b88b8",
    green_shade = "#342d45", selection = "#4b3e63", brown = "#f6c177",
    tan = "#f9dcae", cyan = "#9ccfd8", diff_add_bg = "#24382f",
    diff_add_fg = "#a6daaa", diff_delete_bg = "#4b2934", diff_delete_fg = "#f2a6b3",
    diff_change_bg = "#383047", error = "#eb6f92", warn = "#f6c177",
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

-- Highlights "base" de Neovim (no de un plugin en particular) que
-- tokyonight deja azules/violeta por defecto: la línea de la statusline,
-- CursorLine, selección visual, búsqueda, tabline, line numbers. Esto es
-- lo que queda "de fondo" en cualquier ventana (explorador, buffers,
-- dashboard), a diferencia de dashboard.lua/explorer.lua/statusline.lua
-- que solo pintan sus propios grupos. Se llama una sola vez desde
-- lua/plugins/colorscheme.lua, ahí también se reaplica en ColorScheme.
function M.apply_base_highlights()
  local c = M.colors
  -- Fondo/texto base de CUALQUIER ventana normal (donde no aplica un grupo
  -- más específico): esto es lo que tokyonight deja azul por defecto y
  -- ningún override puntual (dashboard/explorer/statusline) llegaba a
  -- cubrir — de ahí que el azul siguiera "asomando" en archivos sueltos
  -- del árbol, ventanas flotantes, etc.
  vim.api.nvim_set_hl(0, "Normal", { bg = c.bg, fg = c.fg })
  vim.api.nvim_set_hl(0, "NormalNC", { bg = c.bg, fg = c.fg })
  vim.api.nvim_set_hl(0, "NormalFloat", { bg = c.bg_alt, fg = c.fg })
  vim.api.nvim_set_hl(0, "FloatBorder", { bg = c.bg_alt, fg = c.green_dim })
  vim.api.nvim_set_hl(0, "NvimTreeNormal", { bg = c.bg, fg = c.fg })
  vim.api.nvim_set_hl(0, "NvimTreeNormalNC", { bg = c.bg, fg = c.fg })
  vim.api.nvim_set_hl(0, "NvimTreeEndOfBuffer", { fg = c.bg })
  vim.api.nvim_set_hl(0, "NvimTreeWinSeparator", { bg = c.bg, fg = c.green_shade })
  -- Grupo vim genérico (no de un plugin en particular) que tokyonight deja
  -- azul; bufferline.nvim lo usa para el título "Explorer" que aparece
  -- arriba del árbol (ver lua/plugins/editor.lua, offsets.highlight).
  vim.api.nvim_set_hl(0, "Directory", { fg = c.green, bold = true })
  -- bufferline.nvim dibuja el título "Explorer" sobre el tabline nativo de
  -- Neovim: el fondo de esa franja lo pinta "TabLine"/"TabLineFill", no
  -- ningún grupo propio de bufferline (esos ya estaban en la paleta).
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
  -- Paleta de cambios basada en la vista de Git: verde para añadidos y
  -- rojo oscuro para eliminaciones, con texto legible sobre ambos fondos.
  vim.api.nvim_set_hl(0, "DiffAdd", { bg = c.diff_add_bg, fg = c.diff_add_fg })
  vim.api.nvim_set_hl(0, "DiffDelete", { bg = c.diff_delete_bg, fg = c.diff_delete_fg })
  vim.api.nvim_set_hl(0, "DiffChange", { bg = c.diff_change_bg, fg = c.fg })
  vim.api.nvim_set_hl(0, "DiffText", { bg = "#38553d", fg = c.green_bright, bold = true })
  vim.api.nvim_set_hl(0, "DiffviewDiffAdd", { bg = c.diff_add_bg, fg = c.diff_add_fg })
  vim.api.nvim_set_hl(0, "DiffviewDiffDelete", { bg = c.diff_delete_bg, fg = c.diff_delete_fg })
  vim.api.nvim_set_hl(0, "DiffviewDiffAddAsText", { bg = c.diff_add_bg, fg = c.diff_add_fg })
  vim.api.nvim_set_hl(0, "DiffviewDiffDeleteAsText", { bg = c.diff_delete_bg, fg = c.diff_delete_fg })
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

  -- Sintaxis Markdown: evita que Treesitter conserve los azules de TokyoNight
  -- cuando se cambia a la paleta verde, especialmente en enlaces y títulos.
  vim.api.nvim_set_hl(0, "@markup.heading", { fg = c.green, bold = true })
  vim.api.nvim_set_hl(0, "@markup.heading.1", { fg = c.green_bright, bold = true })
  vim.api.nvim_set_hl(0, "@markup.heading.2", { fg = c.green, bold = true })
  vim.api.nvim_set_hl(0, "@markup.link", { fg = c.green, underline = true })
  vim.api.nvim_set_hl(0, "@markup.link.label", { fg = c.green_bright, underline = true })
  vim.api.nvim_set_hl(0, "@markup.link.url", { fg = c.green_dim, underline = true })
  vim.api.nvim_set_hl(0, "@markup.raw", { fg = c.tan, bg = c.bg_alt })
  vim.api.nvim_set_hl(0, "@markup.list", { fg = c.brown })
  vim.api.nvim_set_hl(0, "@punctuation.special", { fg = c.brown })
  vim.api.nvim_set_hl(0, "@string", { fg = c.tan })
  vim.api.nvim_set_hl(0, "@comment", { fg = c.green_dim, italic = true })
  vim.api.nvim_set_hl(0, "SpellBad", { sp = c.brown, undercurl = true })
end

function M.reload()
  vim.cmd.colorscheme("tokyonight")
  M.apply_base_highlights()
  vim.api.nvim_exec_autocmds("User", { pattern = "ThemeChanged" })
  vim.cmd("redraw")
  vim.api.nvim_echo({
    { "Tema activo: ", "Normal" },
    { M.active or "verde", "String" },
  }, false, {})
end

function M.select()
  local names = { "verde", "ambar", "cian", "violeta" }
  vim.ui.select(names, {
    prompt = "Seleccionar tema:",
    snacks = {
      win = { input = { keys = { ["<Esc>"] = { "close", mode = { "n", "i" } } } } },
    },
  }, function(name)
    if not name then
      return
    end
    copy_palette(name)
    vim.fn.mkdir(vim.fn.stdpath("data"), "p")
    vim.fn.writefile({ name }, palette_file)
    M.reload()
  end)
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
