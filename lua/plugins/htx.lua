-- Integración del CLI de higpertext (htx) en nvim. A diferencia de
-- ai_cli.lua (sesiones interactivas persistentes), estos son comandos
-- "one-shot": corren, imprimen su resultado y terminan solos. La ventana
-- flotante se abre para ver el output y se cierra con `q` o al salir del
-- terminal, sin quedar corriendo en segundo plano.
--
-- Uso:
--   :HtxInit [profile]     Inicializar el motor (htx init --assistant claude)
--   :HtxProfile [name]     Cargar un perfil (htx profile load --assistant claude)
--   :HtxRules [ids]        Cargar reglas de capacidades (htx task load-rules --rules ...)
--
--   <leader>hi / <leader>hp / <leader>hl

local DEFAULT_PROFILE = "software_developer"
local DEFAULT_ASSISTANT = "claude"
local DEFAULT_RULES = "all"

local function float_opts(title)
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.7)
  return {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = string.format(" %s (q para cerrar) ", title),
    title_pos = "center",
  }
end

local function run_oneshot(title, cmd)
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, float_opts(title))
  vim.fn.termopen(cmd, {
    on_exit = function()
      vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, desc = "Cerrar " .. title })
    end,
  })
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, desc = "Cerrar " .. title })
  vim.cmd("startinsert")
end

vim.api.nvim_create_user_command("HtxInit", function(cmd_opts)
  local profile = cmd_opts.args ~= "" and cmd_opts.args or DEFAULT_PROFILE
  run_oneshot("htx init", { "htx", "init", profile, "--assistant", DEFAULT_ASSISTANT })
end, { nargs = "?", desc = "htx init [profile]" })

vim.api.nvim_create_user_command("HtxProfile", function(cmd_opts)
  local name = cmd_opts.args ~= "" and cmd_opts.args or DEFAULT_PROFILE
  run_oneshot("htx profile load", { "htx", "profile", "load", name, "--assistant", DEFAULT_ASSISTANT })
end, { nargs = "?", desc = "htx profile load [name]" })

vim.api.nvim_create_user_command("HtxRules", function(cmd_opts)
  local rules = cmd_opts.args ~= "" and cmd_opts.args or DEFAULT_RULES
  run_oneshot("htx load-rules", { "htx", "task", "load-rules", "--rules", rules })
end, { nargs = "?", desc = "htx task load-rules [ids|all]" })

vim.keymap.set("n", "<leader>hi", "<cmd>HtxInit<CR>", { desc = "htx init" })
vim.keymap.set("n", "<leader>hp", "<cmd>HtxProfile<CR>", { desc = "htx profile load" })
vim.keymap.set("n", "<leader>hl", "<cmd>HtxRules<CR>", { desc = "htx load-rules" })

return {}
