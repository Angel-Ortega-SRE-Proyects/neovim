-- La vista docked ("cmdline", pegada a la última fila) rompía la búsqueda
-- por completo: se comprobó en vivo que "/palabra" dejaba de mover el
-- cursor con esa vista. Se usa "cmdline_popup" (la de por defecto), que sí
-- busca bien. El bug del cursor mal ubicado en buffers de terminal que
-- antes se atribuyó a cmdheight=0 en realidad lo resuelve otro fix
-- (desactivar number/signcolumn en TermOpen, ver lua/config/autocmds.lua),
-- así que no hace falta sacrificar la búsqueda por eso.
return {
  "folke/noice.nvim",
  event = "VeryLazy",
  dependencies = {
    "MunifTanjim/nui.nvim",
  },
  opts = {
    cmdline = {
      view = "cmdline_popup",
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
