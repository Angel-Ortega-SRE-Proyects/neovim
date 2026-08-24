-- Paleta única (verde / café / negro) para reemplazar los acentos
-- azul/violeta por defecto de tokyonight en toda la UI custom del config
-- (dashboard, explorador, statusline, etc.). Todos esos archivos importan
-- esta tabla en vez de hardcodear sus propios hex, así un cambio de color
-- acá se propaga a todo el editor de una.
local M = {}

M.colors = {
  bg = "#12120f",
  bg_alt = "#1a1a15", -- fondos secundarios (statusline, pmenu)
  fg = "#c9c9b8",
  green = "#8fbc73", -- acento principal (antes azul de tokyonight)
  green_bright = "#eaf7d8", -- destello / foco
  green_dim = "#7a9b6a", -- texto secundario, footer
  green_shade = "#1c2116", -- fondo casi negro con tinte verde (cursorline)
  selection = "#33421f", -- fondo de selección visual (antes azul)
  brown = "#b08050", -- acento secundario (antes violeta/número)
  tan = "#d7ba89", -- descripciones, texto claro
  error = "#f7768e",
  warn = "#ff9e64",
}

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
  -- Popup de cmdline de noice.nvim (":" / "/" / "?"): border e ícono
  -- heredan de "DiagnosticSignInfo" (cian) por defecto — se pisan acá en
  -- vez de recolorear los diagnósticos en sí, que son un caso aparte.
  vim.api.nvim_set_hl(0, "NoiceCmdlinePopupBorder", { fg = c.green_dim })
  vim.api.nvim_set_hl(0, "NoiceCmdlineIcon", { fg = c.brown })
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
  vim.api.nvim_set_hl(0, "PmenuSel", { bg = c.green_shade, fg = c.green_bright })
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
  vim.api.nvim_set_hl(0, "TelescopeSelection", { bg = c.green_shade, fg = c.green_bright })
  vim.api.nvim_set_hl(0, "TelescopeSelectionCaret", { bg = c.green_shade, fg = c.green })
  vim.api.nvim_set_hl(0, "TelescopeMatching", { fg = c.brown, bold = true })
  vim.api.nvim_set_hl(0, "TelescopePromptPrefix", { fg = c.green })
end

return M
