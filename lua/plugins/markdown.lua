-- Markdown "como lo hace VSCode":
--   1) render-markdown.nvim: renderiza el .md dentro del propio buffer
--      (headings, listas, tablas, code blocks) sin salir de nvim.
--   2) markdown-preview.nvim: abre un preview sincronizado en el navegador
--      con soporte real de Mermaid — la terminal integrada de VSCode no
--      soporta protocolo de imágenes (kitty/sixel), así que el navegador
--      es la única vía confiable para ver diagramas de verdad.
--
-- Uso:
--   <leader>mp   abrir preview en el navegador (Mermaid incluido)
--   <leader>ms   detener el preview
return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    opts = {},
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
      { "<leader>mp", "<cmd>MarkdownPreview<CR>", desc = "Markdown preview (navegador, con Mermaid)", ft = "markdown" },
      { "<leader>ms", "<cmd>MarkdownPreviewStop<CR>", desc = "Detener markdown preview", ft = "markdown" },
    },
  },
}
