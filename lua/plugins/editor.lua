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

      local function set_highlights()
        -- Texto del blame: tenue e itálico para no competir con el código.
        vim.api.nvim_set_hl(0, "GitSignsCurrentLineBlame", { fg = "#565f89", italic = true })
      end
      set_highlights()
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("GitsignsBlameHighlights", { clear = true }),
        callback = set_highlights,
      })

      -- Popup con el detalle completo del commit (autor, fecha, mensaje
      -- completo, archivos cambiados) — igual a la tarjeta que aparece al
      -- hacer hover sobre el blame en VSCode/GitLens.
      -- <leader>gb ya lo usa Telescope (git_branches, ver
      -- lua/plugins/telescope.lua) — el blame de línea va en <leader>gl.
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
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {},
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    event = { "BufReadPost", "BufNewFile" },
    opts = {},
  },
  {
    "akinsho/bufferline.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        mode = "buffers",
        diagnostics = "nvim_lsp",
        show_buffer_close_icons = true,
        show_close_icon = false,
        offsets = {
          {
            filetype = "NvimTree",
            text = "Explorer",
            highlight = "Directory",
            separator = true,
          },
        },
      },
    },
  },
}
