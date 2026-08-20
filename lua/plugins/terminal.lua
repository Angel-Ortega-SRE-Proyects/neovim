-- Terminales integradas, sincronizadas en ambas direcciones con el cwd de
-- Neovim (y por lo tanto con el explorador, que sigue al cwd) — ver
-- lua/config/autocmds.lua para el mecanismo de sincronización (OSC 7).
--
--   :Tf      terminal flotante (ventana encima, para comandos rápidos)
--   :Term    terminal como pestaña normal (buffer en el área de edición,
--            aparece en la barra de buffers igual que un archivo)
--   :Tb      terminal como panel inferior (franja delgada pegada abajo,
--            estilo VSCode) — para moverte, crear/borrar archivos y
--            carpetas (cd, ls, mkdir, touch, rm, mv, etc.) sin perder de
--            vista el editor
--
-- Uso:
--   <C-\>          toggle terminal flotante
--   <leader>tf       toggle terminal flotante
--   (dentro de la flotante) A-hjkl mueve, A-=/A-- redimensiona
--   <leader>tt       abrir/enfocar terminal en pestaña
--   <leader>tb       toggle terminal panel inferior
--   :Tf ls -la       abre la flotante y ejecuta ese comando
--   :Term ls -la      abre la pestaña y ejecuta ese comando
--   :Tb ls -la       abre el panel inferior y ejecuta ese comando
local term_bufnr = nil

local function open_tab_terminal(args)
  if term_bufnr and vim.api.nvim_buf_is_valid(term_bufnr) then
    local win = vim.fn.bufwinid(term_bufnr)
    if win == -1 then
      vim.cmd("buffer " .. term_bufnr)
    else
      vim.api.nvim_set_current_win(win)
    end
  else
    vim.cmd("enew")
    vim.fn.termopen(vim.o.shell)
    term_bufnr = vim.api.nvim_get_current_buf()
  end
  vim.cmd("startinsert")

  if args ~= "" then
    vim.defer_fn(function()
      local job = vim.b[term_bufnr].terminal_job_id
      if job then
        vim.fn.chansend(job, args .. "\n")
      end
    end, 60)
  end
end

vim.api.nvim_create_user_command("Term", function(cmd_opts)
  open_tab_terminal(cmd_opts.args)
end, { nargs = "*", desc = "Terminal como pestaña (opcional: comando a ejecutar)" })

-- :Sys -> monitor de recursos a pantalla completa (top) en ventana flotante.
vim.api.nvim_create_user_command("Sys", function()
  local width = math.floor(vim.o.columns * 0.85)
  local height = math.floor(vim.o.lines * 0.85)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = " Recursos del sistema (q para salir) ",
    title_pos = "center",
  })
  vim.fn.termopen("top", {
    on_exit = function()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end,
  })
  vim.cmd("startinsert")
  vim.keymap.set({ "n", "t" }, "q", "<cmd>q<CR>", { buffer = buf, desc = "Cerrar monitor" })
end, { desc = "Monitor de CPU/memoria a pantalla completa" })

vim.keymap.set("n", "<leader>ts", "<cmd>Sys<CR>", { desc = "System monitor (top)" })

return {
  "akinsho/toggleterm.nvim",
  version = "*",
  event = "VeryLazy",
  keys = {
    { "<C-\\>", "<cmd>Tf<CR>", desc = "Toggle terminal (flotante)", mode = { "n", "t" } },
    { "<leader>tf", "<cmd>Tf<CR>", desc = "Floating terminal" },
    { "<leader>tt", "<cmd>Term<CR>", desc = "Terminal en pestaña" },
    { "<leader>tb", "<cmd>Tb<CR>", desc = "Terminal panel inferior", mode = { "n", "t" } },
  },
  opts = {
    close_on_exit = true,
    float_opts = { border = "curved" },
  },
  config = function(_, opts)
    require("toggleterm").setup(opts)

    -- toggleterm cierra CUALQUIER terminal flotante en WinLeave (ver
    -- handle_term_leave en toggleterm.lua: `if term:is_float() then
    -- term:close() end`), así que un simple click afuera (que dispara
    -- WinLeave al mover el foco) la destruye en vez de solo desenfocarla.
    -- Se quita ese autocmd puntual del grupo interno del plugin para poder
    -- clickear afuera, mover el cursor con <C-hjkl>/mouse, etc. sin que se
    -- cierre; se sigue pudiendo cerrar con <C-\> o :Tf.
    for _, au in ipairs(vim.api.nvim_get_autocmds({ group = "ToggleTermCommands", event = "WinLeave" })) do
      vim.api.nvim_del_autocmd(au.id)
    end

    -- Estado de la flotante: toggleterm no deja arrastrarla con el mouse
    -- (Neovim no soporta eso en floats), así que se mueve/redimensiona a
    -- teclado reescribiendo su win_config en cada paso.
    local float_state = {
      width = math.floor(vim.o.columns * 0.8),
      height = math.floor(vim.o.lines * 0.8),
    }
    float_state.row = math.floor((vim.o.lines - float_state.height) / 2)
    float_state.col = math.floor((vim.o.columns - float_state.width) / 2)

    local float_term = require("toggleterm.terminal").Terminal:new({
      direction = "float",
      close_on_exit = false,
      float_opts = {
        border = "curved",
        width = float_state.width,
        height = float_state.height,
        row = float_state.row,
        col = float_state.col,
      },
      on_open = function(term)
        local function apply()
          vim.api.nvim_win_set_config(term.window, {
            relative = "editor",
            row = float_state.row,
            col = float_state.col,
            width = float_state.width,
            height = float_state.height,
          })
        end

        local function move(drow, dcol)
          float_state.row = math.max(0, math.min(vim.o.lines - float_state.height - 2, float_state.row + drow))
          float_state.col = math.max(0, math.min(vim.o.columns - float_state.width, float_state.col + dcol))
          apply()
        end

        local function resize(dwidth, dheight)
          float_state.width = math.max(20, math.min(vim.o.columns, float_state.width + dwidth))
          float_state.height = math.max(5, math.min(vim.o.lines - 2, float_state.height + dheight))
          apply()
        end

        local step = 3
        local opts = { buffer = term.bufnr }
        for _, mode in ipairs({ "n", "t" }) do
          vim.keymap.set(mode, "<A-h>", function() move(0, -step) end, opts)
          vim.keymap.set(mode, "<A-l>", function() move(0, step) end, opts)
          vim.keymap.set(mode, "<A-k>", function() move(-step, 0) end, opts)
          vim.keymap.set(mode, "<A-j>", function() move(step, 0) end, opts)
          vim.keymap.set(mode, "<A-=>", function() resize(step, step) end, opts)
          vim.keymap.set(mode, "<A-->", function() resize(-step, -step) end, opts)
        end
      end,
    })

    vim.api.nvim_create_user_command("Tf", function(cmd_opts)
      if cmd_opts.args ~= "" then
        float_term:open()
        vim.defer_fn(function()
          float_term:send(cmd_opts.args, false)
        end, 50)
      else
        float_term:toggle()
      end
    end, { nargs = "*", desc = "Floating terminal (opcional: comando a ejecutar)" })

    -- Título con ícono para el panel inferior, ya que a diferencia de la
    -- flotante (que tiene borde+title propio) un split horizontal no
    -- muestra nada por defecto. Se reaplica al cambiar de colorscheme.
    local function set_term_highlights()
      vim.api.nvim_set_hl(0, "ToggletermTitle", { fg = "#7dcfff", bold = true })
    end
    set_term_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("ToggletermTitleHl", { clear = true }),
      callback = set_term_highlights,
    })

    -- Panel inferior: franja horizontal delgada pegada al fondo (estilo
    -- VSCode), para navegar y hacer operaciones básicas de archivos
    -- (cd, ls, mkdir, touch, rm, mv, cp) sin taparte todo el editor.
    local bottom_term = require("toggleterm.terminal").Terminal:new({
      direction = "horizontal",
      size = 12,
      close_on_exit = false,
      on_open = function(term)
        vim.wo[term.window].winbar = "%#ToggletermTitle#  bash · panel inferior%#StatusLine#"
      end,
    })

    vim.api.nvim_create_user_command("Tb", function(cmd_opts)
      if cmd_opts.args ~= "" then
        bottom_term:open()
        vim.defer_fn(function()
          bottom_term:send(cmd_opts.args, false)
        end, 50)
      else
        bottom_term:toggle()
      end
    end, { nargs = "*", desc = "Terminal panel inferior (opcional: comando a ejecutar)" })
  end,
}
