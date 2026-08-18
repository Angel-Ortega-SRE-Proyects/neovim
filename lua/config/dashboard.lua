-- Reemplaza el buffer [No Name] inicial (solo cuando abres `nvim` sin
-- argumentos) por una vista de los comandos disponibles: nombre + qué hace
-- cada uno, agrupados por categoría. Edita GROUPS para mantenerla al día.
local M = {}

local GROUPS = {
  {
    title = "Buscar (Telescope)",
    items = {
      { "<leader>ff", "Buscar archivos" },
      { "<leader>fg", "Buscar texto (live grep)" },
      { "<leader>fb", "Listar buffers abiertos" },
      { "<leader>fh", "Buscar en la ayuda (:help)" },
      { "<leader>fo", "Archivos recientes" },
    },
  },
  {
    title = "Git",
    items = {
      { "<leader>gc", "Historial de commits (con preview)" },
      { "<leader>gs", "Archivos modificados (git status)" },
      { "<leader>gb", "Listar branches" },
      { "<leader>gd  /  :DiffviewOpen", "Panel de diffs de lo cambiado" },
      { "<leader>gh  /  :DiffviewFileHistory %", "Historial del archivo actual" },
    },
  },
  {
    title = "Explorador de archivos",
    items = {
      { "<leader>e", "Mostrar/ocultar el explorador" },
      { "<leader>o", "Enfocar el explorador" },
      { "C  (dentro del explorador)", "Cambiar cwd a la carpeta bajo el cursor" },
    },
  },
  {
    title = "Terminal",
    items = {
      { ":Term [comando]  /  <leader>tt", "Terminal como pestaña normal" },
      { ":Tf [comando]  /  <leader>tf  /  <C-\\>", "Terminal flotante" },
    },
  },
  {
    title = "Sistema",
    items = {
      { ":Sys  /  <leader>ts", "Monitor de CPU/memoria/disco (top)" },
      { "barra de estado", "CPU/MEM/DISK siempre visibles abajo" },
    },
  },
  {
    title = "LSP / código",
    items = {
      { "gd", "Ir a la definición" },
      { "gr", "Ver referencias" },
      { "K", "Documentación (hover)" },
      { "<leader>rn", "Renombrar símbolo" },
      { "<leader>ca", "Code action" },
      { "<leader>d", "Ver diagnóstico en flotante" },
    },
  },
  {
    title = "Autocompletado / Copilot",
    items = {
      { "<Tab>", "Aceptar sugerencia (cmp o Copilot)" },
      { "<M-]> / <M-[>", "Copilot: siguiente / anterior sugerencia" },
      { "<C-]>", "Copilot: descartar sugerencia" },
      { ":Copilot auth", "Iniciar sesión en GitHub Copilot" },
    },
  },
  {
    title = "Edición general",
    items = {
      { "<leader>w  /  <leader>q", "Guardar / salir" },
      { "<C-h/j/k/l>", "Moverse entre ventanas" },
      { "<S-h> / <S-l>", "Buffer anterior / siguiente" },
      { "<leader>bd", "Cerrar buffer" },
    },
  },
}

local function build_lines()
  local lines = {
    "  Comandos disponibles",
    "  ══════════════════════════════════════════════════════════════",
  }

  local name_width = 0
  for _, group in ipairs(GROUPS) do
    for _, item in ipairs(group.items) do
      name_width = math.max(name_width, #item[1])
    end
  end

  for _, group in ipairs(GROUPS) do
    table.insert(lines, "")
    table.insert(lines, "  " .. group.title)
    table.insert(lines, "  " .. string.rep("─", #group.title))
    for _, item in ipairs(group.items) do
      local name, desc = item[1], item[2]
      table.insert(lines, string.format("    %-" .. name_width .. "s   %s", name, desc))
    end
  end

  table.insert(lines, "")
  table.insert(lines, "  Comandos de Vim y de plugins (todos): :command  ·  :h index  ·  :h ex-cmd-index")

  return lines
end

function M.setup()
  vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("CommandsDashboard", { clear = true }),
    callback = function()
      if vim.fn.argc() ~= 0 then
        return
      end
      local buf = vim.api.nvim_get_current_buf()
      if vim.bo[buf].buftype ~= "" or vim.fn.bufname(buf) ~= "" then
        return
      end

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, build_lines())
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].bufhidden = "wipe"
      vim.bo[buf].swapfile = false
      vim.bo[buf].modifiable = false
      vim.bo[buf].filetype = "commandsdashboard"
    end,
  })
end

return M
