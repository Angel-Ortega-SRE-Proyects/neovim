-- Explorador de archivos estilo VSCode (panel lateral fijo).
-- Personaliza a tu gusto: ancho, iconos, comportamiento de apertura, etc.
return {
  "nvim-tree/nvim-tree.lua",
  version = "*",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  lazy = false,
  keys = {
    { "<leader>e", "<cmd>NvimTreeToggle<CR>", desc = "Toggle file explorer" },
    { "<leader>o", "<cmd>NvimTreeFocus<CR>", desc = "Focus file explorer" },
  },
  init = function()
    -- Abre el explorador automáticamente al iniciar (como el Explorer de VSCode)
    vim.api.nvim_create_autocmd("VimEnter", {
      group = vim.api.nvim_create_augroup("NvimTreeAutoOpen", { clear = true }),
      callback = function(data)
        local directory = vim.fn.isdirectory(data.file) == 1
        if directory then
          vim.cmd.cd(data.file)
        end
        require("nvim-tree.api").tree.open()
      end,
    })

    -- Color propio para las carpetas (cerradas, abiertas, vacías) en vez del
    -- gris apagado por defecto. Se reaplica al cambiar de colorscheme.
    local function set_highlights()
      vim.api.nvim_set_hl(0, "NvimTreeFolderIcon", { fg = "#7aa2f7" })
      vim.api.nvim_set_hl(0, "NvimTreeFolderName", { fg = "#c0caf5" })
      vim.api.nvim_set_hl(0, "NvimTreeOpenedFolderName", { fg = "#7dcfff", bold = true })
      vim.api.nvim_set_hl(0, "NvimTreeEmptyFolderName", { fg = "#565f89", italic = true })
      vim.api.nvim_set_hl(0, "NvimTreeIndentMarker", { fg = "#3b4261" })
    end
    set_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("NvimTreeHighlights", { clear = true }),
      callback = set_highlights,
    })
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
      open_file = {
        quit_on_open = false,
        resize_window = true,
      },
    },
    -- Que nvim-tree NO se quede como única ventana al cerrar el último buffer
    tab = { sync = { open = false, close = false } },
  },
}
