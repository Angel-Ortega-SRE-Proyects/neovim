-- La línea de comandos vuelve a ser la nativa de Vim. Noice conserva el
-- menú de sugerencias como una ventana seleccionable, sin convertir ":"
-- ni "/" en un cuadro flotante centrado.
return {
  "folke/noice.nvim",
  event = "VeryLazy",
  dependencies = {
    "MunifTanjim/nui.nvim",
  },
  opts = {
    cmdline = {
      view = "cmdline",
      format = {
        -- Mismo ícono que usa el panel de terminal (lua/plugins/terminal.lua)
        -- para ":!" (filtro por comando externo), en vez del "$" por defecto.
        filter = { pattern = "^:%s*!", icon = "", lang = "bash" },
      },
    },
    messages = {
      view = "mini",
      view_error = "mini",
      view_warn = "mini",
    },
    popupmenu = {
      backend = "nui",
    },
    views = {
      popupmenu = {
        relative = "editor",
        position = { row = "76%", col = "50%" },
        size = { width = 80, height = 8 },
        border = {
          style = "rounded",
          padding = { 0, 1 },
        },
      },
    },
    presets = {
      bottom_search = false,
      command_palette = false,
      long_message_to_split = true,
    },
  },
  config = function(_, opts)
    vim.o.cmdheight = 1
    require("noice").setup(opts)
  end,
}
