local map = vim.keymap.set
local t = require("config.i18n").t
local M = {}

-- Window navigation: ver lua/plugins/smart-splits.lua (C-Flechas cruza también
-- hacia panes de tmux, no solo splits de Neovim).
local WINDOW_DIRECTIONS = {
  ["<leader><Left>"] = { smart_splits = "move_cursor_left", vim_direction = "h", label = "izquierdo" },
  ["<leader><Down>"] = { smart_splits = "move_cursor_down", vim_direction = "j", label = "inferior" },
  ["<leader><Up>"] = { smart_splits = "move_cursor_up", vim_direction = "k", label = "superior" },
  ["<leader><Right>"] = { smart_splits = "move_cursor_right", vim_direction = "l", label = "derecho" },
}

for _, key in ipairs({ "<leader>Sl", "<leader>Sd" }) do
  pcall(vim.keymap.del, "n", key)
end

function M.setup_window_navigation()
  for key, direction in pairs(WINDOW_DIRECTIONS) do
    map("n", key, function()
      local ok, smart_splits = pcall(require, "smart-splits")
      if ok then
        smart_splits[direction.smart_splits]()
      else
        vim.cmd("wincmd " .. direction.vim_direction)
      end
    end, { desc = t("Ir a división/panel " .. direction.label .. " (Espacio + flecha)") })
  end
end

function M.setup_format_menu()
  vim.api.nvim_create_user_command("Format", function()
    require("conform").format({ async = true, lsp_format = "fallback" })
  end, { desc = "Formatear el archivo o selección actual", force = true })
  vim.cmd("silent! aunmenu PopUp.Format")
  vim.cmd("amenu PopUp.Format :Format<CR>")
end

function M.setup_explorer_navigation()
  map("n", "<leader>ep", function()
    local ok, api = pcall(require, "nvim-tree.api")
    if ok then
      api.tree.change_root_to_parent()
    end
  end, { desc = "Subir a la carpeta padre en el explorador" })
end

-- Buffers
map("n", "<S-h>", ":bprevious<CR>", { desc = t("Búfer anterior") })
map("n", "<S-l>", ":bnext<CR>", { desc = t("Búfer siguiente") })

-- Editing
map("n", "<Esc>", ":nohlsearch<CR>", { desc = t("Limpiar resaltado de búsqueda") })
map("n", "<leader>uc", "<cmd>ThemeSelect<CR>", { desc = t("Cambiar tema de colores") })
map("n", "<leader>ul", "<cmd>LanguageSelect<CR>", { desc = t("Cambiar idioma de la interfaz") })
map("c", "<Down>", function()
  return vim.fn.wildmenumode() == 1 and "<C-n>" or "<Down>"
end, { expr = true, replace_keycodes = true, desc = "Siguiente sugerencia de comando" })
map("c", "<Up>", function()
  return vim.fn.wildmenumode() == 1 and "<C-p>" or "<Up>"
end, { expr = true, replace_keycodes = true, desc = "Sugerencia anterior de comando" })
map("c", "<Esc>", "<C-c>", { desc = "Cancelar comando y cerrar sugerencias" })
map("v", "<", "<gv", { desc = "Reducir indentación" })
map("v", ">", ">gv", { desc = "Aumentar indentación" })
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Mover selección abajo" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Mover selección arriba" })

-- File explorer / search (placeholders for plugin keymaps set in lua/plugins)
map("n", "<C-s>", ":update<CR>", { desc = "Guardar cambios" })
map("i", "<C-s>", "<C-o>:update<CR>", { desc = "Guardar cambios" })
map("n", "<leader>aq", function()
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    local ok, is_agent_hub = pcall(vim.api.nvim_tabpage_get_var, tabpage, "agent_hub")
    if ok and is_agent_hub then
      vim.api.nvim_set_current_tabpage(tabpage)
      vim.cmd("tabclose!")
      return
    end
  end
  vim.notify("AgentHub no está abierto", vim.log.levels.INFO)
end, { desc = "Cerrar AgentHub sin detener agentes", nowait = true, silent = true })

M.setup_window_navigation()
M.setup_format_menu()
M.setup_explorer_navigation()

return M
