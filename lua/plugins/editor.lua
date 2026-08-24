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
            text = "  Explorer",
            text_align = "left",
            highlight = "Directory",
            separator = true,
          },
        },
        -- Barra de "arriba": rama + cambios sin commitear de la rama actual
        -- + recursos del sistema (CPU/MEM/DISK/NET, antes en la barra de
        -- abajo -- ver lua/config/statusline.lua). Bufferline no repinta
        -- esto solo, así que hay un timer más abajo que fuerza
        -- :redrawtabline cada 2s (mismo patrón que el redrawstatus de
        -- statusline.lua para el indicador de agentes).
        custom_areas = {
          -- Tokens usados (y costo aproximado) por la sesión ACTIVA de cada
          -- agente de IA en esta carpeta -- lua/config/agent_usage.lua hace
          -- el parseo real (JSONL/sqlite de cada CLI) en segundo plano.
          left = function()
            local colors = require("config.theme").colors
            local usage = require("config.agent_usage")

            local function esc(text)
              return (text:gsub("%%", "%%%%"))
            end

            local function fmt_tokens(n)
              if n >= 1000000 then
                return string.format("%.1fM", n / 1000000)
              elseif n >= 1000 then
                return string.format("%.1fK", n / 1000)
              end
              return tostring(n)
            end

            local total = usage.total()
            if total.tokens == 0 then
              return {}
            end

            local text = "  " .. fmt_tokens(total.tokens) .. " tok"
            if total.cost then
              text = text .. string.format(" · %s$%.2f", total.is_estimate and "~" or "", total.cost)
            end

            return { { text = esc(text .. "  "), fg = colors.brown } }
          end,
          right = function()
            local colors = require("config.theme").colors
            local git = require("config.git")
            local sysmonitor = require("config.sysmonitor")

            -- bufferline mide cada texto con nvim_eval_statusline, que lo
            -- trata como una EXPRESIÓN de statusline: un "%" suelto ahí
            -- (ej. el "12%" de CPU) no es texto literal, arranca un ítem
            -- -- hay que escaparlo como "%%" para que se muestre tal cual.
            local function esc(text)
              return (text:gsub("%%", "%%%%"))
            end

            local segs = {}

            local branch = git.branch()
            if branch ~= "" then
              table.insert(segs, { text = esc("  " .. branch .. " "), fg = colors.brown })
              local stat = git.diff_stat()
              if stat then
                table.insert(segs, {
                  text = esc(string.format("⇕ %d archivo%s +%d -%d  ", stat.files, stat.files == 1 and "" or "s", stat.add, stat.del)),
                  fg = colors.warn,
                })
              end
            end

            table.insert(segs, { text = esc(sysmonitor.status() .. " "), fg = colors.green_dim })

            return segs
          end,
        },
      },
    },
    config = function(_, opts)
      require("config.sysmonitor").start(3000)
      -- 15s, no 2-3s como sysmonitor: cada tick lee JSONL/sqlite de disco
      -- (5 herramientas), no vale la pena hacerlo tan seguido.
      require("config.agent_usage").start(15000)
      require("bufferline").setup(opts)

      local timer = vim.uv.new_timer()
      timer:start(
        2000,
        2000,
        vim.schedule_wrap(function()
          pcall(vim.cmd.redrawtabline)
        end)
      )
    end,
  },
}
