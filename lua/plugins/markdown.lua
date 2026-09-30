-- Markdown "como lo hace VSCode":
--   1) render-markdown.nvim: renderiza el .md dentro del propio buffer
--      (headings, listas, tablas, code blocks) sin salir de nvim.
--   2) markdown-preview.nvim: abre un preview sincronizado en el navegador
--      con soporte real de Mermaid — la terminal integrada de VSCode no
--      soporta protocolo de imágenes (kitty/sixel), así que el navegador
--      es la única vía confiable para ver diagramas de verdad.
--
-- Uso:
--   <leader>mv   abrir una vista renderizada al lado
--   <leader>mp   abrir preview en el navegador (Mermaid incluido)
--   <leader>ms   detener el preview
local t = require("config.i18n").t

return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    opts = {
      -- Evita que documentos generados muy grandes ralenticen el editor.
      max_file_size = 2.0,
      -- Renderiza Markdown en la vista normal; al entrar en insertar se
      -- conserva la sintaxis fuente para editar sin que los adornos estorben.
      render_modes = { "n", "c" },
      heading = {
        width = "block",
        position = "inline",
        sign = false,
        icons = { "", "", "", "", "", "" },
        left_margin = 1,
        right_pad = 1,
        -- Línea virtual en blanco arriba y abajo de cada título para
        -- separarlo del texto (invisible: mismo color que el fondo).
        border = true,
        border_virtual = true,
        above = " ",
        below = " ",
      },
      -- Texto, listas y código con más sangría que los títulos (margen 1)
      -- para que se note a qué título pertenecen.
      paragraph = {
        left_margin = 3,
      },
      bullet = {
        icons = { "▸", "▹", "▪", "▫" },
        left_pad = 2,
      },
      code = {
        -- Bloques de código con bordes superior/inferior para distinguirlos
        -- del texto que los rodea.
        border = "thin",
        width = "block",
        left_margin = 3,
        left_pad = 1,
        right_pad = 1,
        language_icon = false,
        language_pad = 1,
        language_border = " ",
      },
      pipe_table = {
        style = "normal",
        padding = 1,
      },
      win_options = {
        wrap = { default = vim.o.wrap, rendered = true },
        linebreak = { default = vim.o.linebreak, rendered = true },
        -- Las líneas envueltas de un ítem siguen alineadas con su texto.
        breakindent = { default = vim.o.breakindent, rendered = true },
        number = { default = vim.o.number, rendered = false },
        relativenumber = { default = vim.o.relativenumber, rendered = false },
      },
    },
    keys = {
      { "<leader>mv", "<cmd>RenderMarkdown preview<CR>", desc = "Vista Markdown al lado", ft = "markdown" },
    },
    config = function(_, opts)
      require("render-markdown").setup(opts)

      local function apply_markdown_highlights()
        local colors = require("config.theme").colors
        local heading_fg = {
          colors.green_bright, colors.tan, colors.cyan,
          colors.brown, colors.green, colors.green_dim,
        }
        for level = 1, 6 do
          vim.api.nvim_set_hl(0, "RenderMarkdownH" .. level .. "Bg", { bg = colors.bg })
          vim.api.nvim_set_hl(0, "RenderMarkdownH" .. level, {
            fg = heading_fg[level],
            bg = colors.bg,
            bold = true,
          })
        end

        local code_bg = colors.bg_alt
        vim.api.nvim_set_hl(0, "RenderMarkdownCode", { bg = code_bg })
        vim.api.nvim_set_hl(0, "RenderMarkdownCodeBorder", { bg = code_bg })
        vim.api.nvim_set_hl(0, "RenderMarkdownCodeInfo", { fg = colors.tan, bg = code_bg, bold = true })
        vim.api.nvim_set_hl(0, "RenderMarkdownTableHead", { fg = colors.green, bg = colors.bg, bold = true })
        vim.api.nvim_set_hl(0, "RenderMarkdownTableRow", { fg = colors.fg, bg = colors.bg })
      end

      apply_markdown_highlights()
      vim.api.nvim_create_autocmd("User", {
        pattern = "ThemeChanged",
        group = vim.api.nvim_create_augroup("RenderMarkdownTheme", { clear = true }),
        callback = apply_markdown_highlights,
      })
    end,
  },
  {
    "iamcco/markdown-preview.nvim",
    ft = { "markdown" },
    build = function()
      vim.fn["mkdp#util#install"]()
    end,
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
      vim.g.mkdp_auto_close = false
      vim.g.mkdp_theme = "dark"

      -- Mermaid se renderiza como SVG real dentro de la página, por lo que
      -- zoom y desplazamiento ya son nativos del navegador:
      --   Ctrl+scroll / pellizcar  -> zoom (vectorial, no se pixela)
      --   scroll normal / drag     -> moverse por el diagrama
      -- Aquí solo se ajusta el tema del diagrama para que combine con el
      -- fondo oscuro del preview, y useMaxWidth=false para que no se
      -- encoja a la fuerza y se pueda de verdad hacer zoom/scroll sobre él.
      vim.g.mkdp_preview_options = {
        maid = {
          theme = "dark",
          flowchart = { useMaxWidth = false },
          sequence = { useMaxWidth = false },
        },
        disable_sync_scroll = 0,
        sync_scroll_type = "middle",
        hide_yaml_meta = 1,
      }
    end,
    keys = {
      { "<leader>mp", "<cmd>MarkdownPreview<CR>", desc = t("Vista previa Markdown (navegador, con Mermaid)"), ft = "markdown" },
      { "<leader>ms", "<cmd>MarkdownPreviewStop<CR>", desc = t("Detener vista previa Markdown"), ft = "markdown" },
    },
  },
}
