local t = require("config.i18n").t

return {
  {
    "williamboman/mason.nvim",
    cmd = "Mason",
    opts = {},
  },
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim" },
    opts = {
      ensure_installed = {
        "lua_ls",
        -- YAML/JSON + devops
        "yamlls", "jsonls", "dockerls", "terraformls", "bashls",
        -- Lenguajes de propósito general
        "pyright", "ruff", "ts_ls", "gopls", "jdtls", "omnisharp",
      },
      automatic_installation = true,
    },
  },
  {
    -- Esquemas JSON (SchemaStore) para que yamlls/jsonls validen contra
    -- Kubernetes, GitHub Actions, docker-compose, etc. automáticamente
    -- según el nombre/contenido del archivo, sin configurarlo a mano.
    "b0o/schemastore.nvim",
    lazy = true,
  },
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "hrsh7th/cmp-nvim-lsp", "b0o/schemastore.nvim" },
    config = function()
      -- API nuevo (vim.lsp.config/enable, Neovim 0.11+) en vez de
      -- require("lspconfig").<server>.setup() — ese framework viejo quedó
      -- deprecado y con 11 servidores tira el warning (con traceback) una
      -- vez por cada uno al arrancar. nvim-lspconfig sigue siendo
      -- dependencia: son sus lsp/*.lua (cmd, filetypes, root_markers de
      -- cada server) los que vim.lsp.config() usa como base.
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("LspKeymaps", { clear = true }),
        callback = function(event)
          local map = function(keys, fn, desc)
            vim.keymap.set("n", keys, fn, { buffer = event.buf, desc = "LSP: " .. t(desc) })
          end
          map("gd", vim.lsp.buf.definition, "Ir a la definición")
          map("gr", vim.lsp.buf.references, "Ir a las referencias")
          map("K", vim.lsp.buf.hover, "Mostrar documentación")
          map("<leader>rn", vim.lsp.buf.rename, "Renombrar símbolo")
          map("<leader>d", vim.diagnostic.open_float, "Diagnóstico flotante")
        end,
      })

      -- Default compartido por todos los servidores.
      vim.lsp.config("*", { capabilities = capabilities })

      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            diagnostics = { globals = { "vim" } },
            workspace = { checkThirdParty = false },
          },
        },
      })

      -- YAML/JSON + devops --------------------------------------------
      vim.lsp.config("yamlls", {
        settings = {
          yaml = {
            schemaStore = { enable = false, url = "" }, -- lo maneja schemastore.nvim
            schemas = require("schemastore").yaml.schemas(),
            validate = true,
          },
        },
      })
      vim.lsp.config("jsonls", {
        settings = {
          json = {
            schemas = require("schemastore").json.schemas(),
            validate = { enable = true },
          },
        },
      })

      -- Python -----------------------------------------------------------
      -- ruff da diagnósticos/lint rápido; pyright el análisis de tipos y
      -- goto-def. Se desactiva el hover de ruff para no duplicar el de
      -- pyright (dos LSP en el mismo buffer, cada uno aporta lo suyo).
      vim.lsp.config("ruff", {
        on_attach = function(client)
          client.server_capabilities.hoverProvider = false
        end,
      })

      -- C#/.NET --------------------------------------------------------
      vim.lsp.config("omnisharp", { cmd = { "omnisharp" } })

      -- dockerls, terraformls, bashls, pyright, ts_ls, gopls, jdtls: van
      -- con la config default de nvim-lspconfig, sin nada para pisar.
      vim.lsp.enable({
        "lua_ls",
        "yamlls", "jsonls", "dockerls", "terraformls", "bashls",
        "pyright", "ruff", "ts_ls", "gopls", "jdtls", "omnisharp",
      })
    end,
  },
}
