return {
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      -- Blame de la línea actual como texto al final de línea: autor, hace
      -- cuánto y el resumen del commit — el equivalente al blame que
      -- VSCode/GitLens muestra en su barra inferior.
      current_line_blame = true,
      current_line_blame_opts = {
        delay = 300,
        virt_text_pos = "eol",
      },
      current_line_blame_formatter = "   <author>, <author_time:%R> · <summary>",
    },
    config = function(_, opts)
      require("gitsigns").setup(opts)

      local colors = require("config.theme").colors
      local function set_highlights()
        -- Texto del blame: tenue e itálico para no competir con el código.
        -- Paleta centralizada en lua/config/theme.lua.
        vim.api.nvim_set_hl(0, "GitSignsCurrentLineBlame", { fg = colors.green_dim, italic = true })
      end
      set_highlights()
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("GitsignsBlameHighlights", { clear = true }),
        callback = set_highlights,
      })

      -- Popup con el detalle completo del commit (autor, fecha, mensaje
      -- completo, archivos cambiados) — igual a la tarjeta que aparece al
      -- hacer hover sobre el blame en VSCode/GitLens.
      -- El modo Git concentra commits, ramas, estado y diffs; el blame de
      -- línea permanece en <leader>gl.
      vim.keymap.set("n", "<leader>gl", function()
        require("gitsigns").blame_line({ full = true })
      end, { desc = "Detalle del commit de esta línea (blame completo)" })
    end,
  },
  {
    "numToStr/Comment.nvim",
    event = { "BufReadPost", "BufNewFile" },
    opts = {},
  },
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts = {},
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    event = { "BufReadPost", "BufNewFile" },
    opts = {},
  },
}
