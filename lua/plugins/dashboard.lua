-- Pantalla de inicio estilo LazyVim (logo + botones), al abrir `nvim` sin
-- argumentos. Reemplaza la vista de texto plano de lua/config/dashboard.lua
-- (esa queda como comando :Commands, ver ahí).

return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    dashboard = {
      enabled = true,
      preset = {
        header = table.concat({
          "██████╗ ███████╗██╗   ██╗███████╗███████╗ ██████╗ ██████╗ ██████╗ ███████╗",
          "██╔══██╗██╔════╝██║   ██║██╔════╝██╔════╝██╔════╝██╔═══██╗██╔══██╗██╔════╝",
          "██║  ██║█████╗  ██║   ██║███████╗█████╗  ██║     ██║   ██║██████╔╝███████╗",
          "██║  ██║██╔══╝  ╚██╗ ██╔╝╚════██║██╔══╝  ██║     ██║   ██║██╔═══╝ ╚════██║",
          "██████╔╝███████╗ ╚████╔╝ ███████║███████╗╚██████╗╚██████╔╝██║     ███████║",
          "╚═════╝ ╚══════╝  ╚═══╝  ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝     ╚══════╝",
        }, "\n"),
        keys = {
          { icon = " ", key = "f", desc = "Buscar archivos", action = ":Telescope find_files" },
          { icon = " ", key = "g", desc = "Buscar texto (live grep)", action = ":Telescope live_grep" },
          { icon = " ", key = "r", desc = "Archivos recientes", action = ":Telescope oldfiles" },
          { icon = " ", key = "p", desc = "Carpetas recientes (Open Recent)", action = ":Projects" },
          { icon = " ", key = "e", desc = "Explorador de archivos", action = ":NvimTreeFocus" },
          { icon = " ", key = "n", desc = "Nuevo archivo", action = ":ene | startinsert" },
          { icon = " ", key = "q", desc = "Salir", action = ":confirm qa" },
        },
      },
    },
  },
  config = function(_, opts)
    -- Paleta verde/café/negro para el dashboard en vez del azul/violeta de
    -- tokyonight (Header/Footer heredan de "Title", Icon/Desc de "Special",
    -- Key de "Number" — todos azulados por defecto). Colores centralizados
    -- en lua/config/theme.lua — la usan también explorer.lua y
    -- statusline.lua, así queda un único lugar para tocar. Se reaplica al
    -- cambiar de colorscheme, igual que el resto del config.
    local colors = require("config.theme").colors
    local function set_highlights()
      vim.api.nvim_set_hl(0, "SnacksDashboardHeader", { fg = colors.green, bold = true })
      vim.api.nvim_set_hl(0, "SnacksDashboardTitle", { fg = colors.green, bold = true })
      vim.api.nvim_set_hl(0, "SnacksDashboardDesc", { fg = colors.tan })
      vim.api.nvim_set_hl(0, "SnacksDashboardIcon", { fg = colors.green })
      vim.api.nvim_set_hl(0, "SnacksDashboardKey", { fg = colors.brown, bold = true })
      vim.api.nvim_set_hl(0, "SnacksDashboardFooter", { fg = colors.green_dim, italic = true })
      vim.api.nvim_set_hl(0, "SnacksDashboardNormal", { fg = colors.fg, bg = colors.bg })
      -- "special" es el hl que usa la sección de startup ("9/34 plugins in
      -- Xms") y por defecto hereda de "Special" (celeste de tokyonight) —
      -- sin este override es el único resto de azul que queda en pantalla.
      vim.api.nvim_set_hl(0, "SnacksDashboardSpecial", { fg = colors.brown, bold = true })
      vim.api.nvim_set_hl(0, "SnacksDashboardFile", { fg = colors.tan })
      vim.api.nvim_set_hl(0, "SnacksDashboardDir", { fg = colors.green_dim })
    end
    set_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("SnacksDashboardHighlights", { clear = true }),
      callback = set_highlights,
    })

    require("snacks").setup(opts)

    local group = vim.api.nvim_create_augroup("SnacksDashboardFx", { clear = true })
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = { "SnacksDashboardOpened", "SnacksDashboardUpdatePost" },
      callback = function()
        vim.schedule(function()
          -- snacks apaga la barra de estado (laststatus=0) mientras el
          -- dashboard está abierto y solo la restaura al salir; acá se
          -- vuelve a prender de una, para que quede visible (CPU/MEM/DISK,
          -- git branch, etc. — ver lua/config/options.lua) también en la
          -- pantalla de inicio, no solo al abrir un archivo.
          vim.o.laststatus = 3
        end)
      end,
    })
  end,
}
