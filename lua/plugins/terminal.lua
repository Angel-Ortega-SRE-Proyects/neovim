-- Terminales integradas, sincronizadas en ambas direcciones con el cwd de
-- Neovim (y por lo tanto con el explorador, que sigue al cwd) — ver
-- lua/config/autocmds.lua para el mecanismo de sincronización (OSC 7).
--
--   :Tf      terminal flotante (ventana encima, para comandos rápidos)
--   :Term    terminal como pestaña normal (buffer en el área de edición,
--            aparece en la barra de buffers igual que un archivo)
--
-- Uso:
--   <C-\>          toggle terminal flotante
--   <leader>tf       toggle terminal flotante
--   <leader>tt       abrir/enfocar terminal en pestaña
--   :Tf ls -la       abre la flotante y ejecuta ese comando
--   :Term ls -la      abre la pestaña y ejecuta ese comando
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
  },
  opts = {
    close_on_exit = true,
    float_opts = { border = "curved" },
  },
  config = function(_, opts)
    require("toggleterm").setup(opts)

    local float_term = require("toggleterm.terminal").Terminal:new({
      direction = "float",
      close_on_exit = false,
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
  end,
}
