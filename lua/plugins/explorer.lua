-- Explorador de archivos estilo VSCode (panel lateral fijo).
-- Personaliza a tu gusto: ancho, iconos, comportamiento de apertura, etc.
local t = require("config.i18n").t

return {
  "nvim-tree/nvim-tree.lua",
  version = "*",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  lazy = false,
  keys = {
    { "<leader>e", "<cmd>NvimTreeToggle<CR>", desc = t("Mostrar/ocultar explorador") },
    { "<leader>eh", "<cmd>FilesHidden<CR>", desc = t("Alternar archivos ocultos") },
  },
  init = function()
    vim.api.nvim_create_user_command("FilesHidden", function()
      require("nvim-tree.api").filter.dotfiles.toggle()
      vim.notify("Filtro de archivos ocultos alternado", vim.log.levels.INFO)
    end, { desc = "Mostrar u ocultar archivos dotfile en NvimTree" })

    -- El explorador arranca CERRADO por defecto (ni con `nvim`, ni con
    -- `nvim <carpeta>`) — se abre a mano con <leader>e o :NvimTreeFocus, o desde
    -- el botón "e" del dashboard. Con `nvim <carpeta>` sí cambia el cwd
    -- a esa carpeta, para que quede lista si después abrís el árbol.
    vim.api.nvim_create_autocmd("VimEnter", {
      group = vim.api.nvim_create_augroup("NvimTreeAutoOpen", { clear = true }),
      callback = function(data)
        local directory = data.file ~= "" and vim.fn.isdirectory(data.file) == 1
        if directory then
          vim.cmd.cd(data.file)
        end
      end,
    })

    -- Color propio para las carpetas (cerradas, abiertas, vacías) en vez del
    -- azul/gris por defecto. Paleta centralizada en lua/config/theme.lua
    -- (la misma que usan dashboard.lua y statusline.lua). Se reaplica al
    -- cambiar de colorscheme.
    local colors = require("config.theme").colors
    local function set_highlights()
      vim.api.nvim_set_hl(0, "NvimTreeFolderIcon", { fg = colors.green })
      vim.api.nvim_set_hl(0, "NvimTreeFolderName", { fg = colors.tan })
      vim.api.nvim_set_hl(0, "NvimTreeOpenedFolderName", { fg = colors.green_bright, bold = true })
      vim.api.nvim_set_hl(0, "NvimTreeEmptyFolderName", { fg = colors.green_dim, italic = true })
      vim.api.nvim_set_hl(0, "NvimTreeIndentMarker", { fg = colors.brown })
      vim.api.nvim_set_hl(0, "NvimTreeGitDirty", { fg = colors.warn, bold = true })
      vim.api.nvim_set_hl(0, "NvimTreeGitStaged", { fg = colors.warn, bold = true })
      vim.api.nvim_set_hl(0, "NvimTreeGitMerge", { fg = colors.warn, bold = true })
      vim.api.nvim_set_hl(0, "NvimTreeGitDirtyIcon", { fg = colors.warn, bold = true })
      vim.api.nvim_set_hl(0, "NvimTreeGitStagedIcon", { fg = colors.warn, bold = true })
      vim.api.nvim_set_hl(0, "NvimTreeGitMergeIcon", { fg = colors.warn, bold = true })
      vim.api.nvim_set_hl(0, "NvimTreeGitNew", { fg = colors.cyan, bold = true })
      vim.api.nvim_set_hl(0, "NvimTreeGitNewIcon", { fg = colors.cyan, bold = true })
      vim.api.nvim_set_hl(0, "NvimTreeGitIgnored", { fg = colors.green_dim })
      vim.api.nvim_set_hl(0, "NvimTreeGitIgnoredIcon", { fg = colors.green_dim })
      vim.api.nvim_set_hl(0, "NvimTreeGitDeleted", { fg = colors.error, bold = true })
      vim.api.nvim_set_hl(0, "NvimTreeGitDeletedIcon", { fg = colors.error, bold = true })
      vim.api.nvim_set_hl(0, "NvimTreeGitRenamed", { fg = colors.green, bold = true })
      vim.api.nvim_set_hl(0, "NvimTreeGitRenamedIcon", { fg = colors.green, bold = true })
    end
    set_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("NvimTreeHighlights", { clear = true }),
      callback = set_highlights,
    })

    -- Línea separadora entre el título "Explorer" (lo dibuja bufferline
    -- sobre el tabline, ver lua/plugins/editor.lua) y el listado de
    -- archivos: un winbar propio de la ventana del árbol, que se ubica
    -- justo debajo del tabline y arriba del contenido del buffer. Se pone
    -- en el evento TreeOpen (no FileType: ese dispara mientras nvim-tree
    -- todavía está armando la ventana y bufwinid() puede devolver -1).
    require("nvim-tree.api").events.subscribe("TreeOpen", function()
      local win = require("nvim-tree.api").tree.winid()
      if win and win ~= -1 then
        vim.wo[win].winbar = "%#NvimTreeWinSeparator#" .. string.rep("─", 200)
      end
    end)
  end,
  opts = {
    -- Sin esto, el árbol ignora los :cd (incluido el que dispara la
    -- sincronización OSC7 desde la terminal integrada) y nunca cambia de raíz.
    sync_root_with_cwd = true,
    view = {
      width = 32,
      side = "left",
      signcolumn = "yes",
    },
    renderer = {
      group_empty = true,
      root_folder_label = false,
      highlight_git = true,
      highlight_opened_files = "name",
      indent_markers = { enable = true },
      icons = {
        show = {
          file = true,
          folder = true,
          folder_arrow = true,
          git = true,
        },
        glyphs = {
          folder = {
            arrow_closed = "",
            arrow_open = "",
            default = "",
            open = "",
            empty = "",
            empty_open = "",
            symlink = "",
            symlink_open = "",
          },
          git = {
            unstaged = "M",
            staged = "M",
            unmerged = "M",
            renamed = "R",
            untracked = "?",
            deleted = "D",
            ignored = "",
          },
        },
      },
    },
    diagnostics = {
      enable = true,
      show_on_dirs = true,
    },
    git = {
      enable = true,
      ignore = false,
    },
    filters = {
      dotfiles = false,
      custom = { "^.git$" },
    },
    update_focused_file = {
      enable = true,
      update_root = false,
    },
    actions = {
      -- El portapapeles Wayland no está disponible en esta sesión; usa el
      -- registro interno de NvimTree para que c/y/gy no generen errores.
      use_system_clipboard = false,
      open_file = {
        quit_on_open = false,
        resize_window = true,
      },
    },
    -- Que nvim-tree NO se quede como única ventana al cerrar el último buffer
    tab = { sync = { open = false, close = false } },
  },
}
