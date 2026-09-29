local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

-- Highlight on yank
autocmd("TextYankPost", {
  group = augroup("HighlightYank", { clear = true }),
  callback = function()
    vim.highlight.on_yank({ timeout = 150 })
  end,
})

-- Trim trailing whitespace on save
autocmd("BufWritePre", {
  group = augroup("TrimWhitespace", { clear = true }),
  pattern = "*",
  command = [[%s/\s\+$//e]],
})

-- Muestra el mensaje del diagnóstico (warning/error) automáticamente en un
-- flotante al detenerte sobre esa línea/palabra, sin tener que pulsar
-- <leader>d cada vez. updatetime=250 (options.lua) controla qué tan rápido
-- dispara.
autocmd("CursorHold", {
  group = augroup("DiagnosticHover", { clear = true }),
  callback = function()
    if vim.bo.filetype == "NvimTree" then
      return
    end
    vim.diagnostic.open_float(nil, { focusable = false, scope = "cursor", border = "rounded" })
  end,
})

-- Lo mismo pero en el explorador: al detenerte sobre un archivo con
-- warning/error (el ⚠ que se ve en el árbol), muestra sus mensajes.
autocmd("FileType", {
  pattern = "NvimTree",
  group = augroup("NvimTreeDiagnosticHover", { clear = true }),
  callback = function(args)
    autocmd("CursorHold", {
      buffer = args.buf,
      group = augroup("NvimTreeDiagnosticHoverBuf" .. args.buf, { clear = true }),
      callback = function()
        local ok, api = pcall(require, "nvim-tree.api")
        if not ok then
          return
        end
        local node = api.tree.get_node_under_cursor()
        if not node or node.type ~= "file" then
          return
        end
        local bufnr = vim.fn.bufnr(node.absolute_path)
        if bufnr == -1 then
          return
        end
        local diags = vim.diagnostic.get(bufnr)
        if #diags == 0 then
          return
        end
        local lines = {}
        for _, d in ipairs(diags) do
          table.insert(lines, string.format("[%s] %s", vim.diagnostic.severity[d.severity], d.message))
        end
        vim.lsp.util.open_floating_preview(lines, "plaintext", { border = "rounded", focusable = false })
      end,
    })
  end,
})

-- Terminal <-> Neovim/Explorer cwd sync, para cualquier buffer de terminal
-- (:Term como pestaña, o un :terminal a pelo — :Tb es un pane de tmux
-- real, no un buffer de Neovim, así que no le aplica esto).
--
-- Evita "nvim dentro de nvim dentro de nvim": si dentro de una terminal
-- integrada escribes `nvim <algo>`, en vez de abrir un Neovim anidado,
-- reutiliza ESTA instancia (usa $NVIM, que Neovim ya exporta a sus
-- terminales) — si es la misma carpeta no hace nada (solo avisa), si es
-- otra o un archivo, se lo manda a la instancia ya abierta.
--
-- La función vive en ~/.bashrc.d/nvim-remote.sh y se carga sola en
-- cualquier shell interactiva; antes se re-inyectaba acá vía chansend en
-- cada TermOpen como respaldo, pero eso hacía que se "tipeara" sola y
-- visible cada vez que se abría una terminal — ya no hace falta.

-- El gutter de números (sobre todo relativenumber, que cambia de ancho) y el
-- signcolumn desalinean dónde Neovim dibuja el cursor real de la terminal
-- vs. donde el pty escribe. Se desactivan solo dentro del buffer de terminal.
autocmd("TermOpen", {
  group = augroup("TermNoGutter", { clear = true }),
  callback = function(args)
    vim.wo.number = false
    vim.wo.relativenumber = false
    vim.wo.signcolumn = "no"
    vim.wo.cursorline = false
  end,
})

-- <Esc> en modo terminal sale al modo normal para que los atajos globales
-- (incluidos los que empiezan con <leader>) funcionen también dentro de una
-- terminal abierta en el área del editor. <C-q> queda como alternativa
-- explícita para terminales que necesiten conservar el comportamiento de Esc.
autocmd("TermOpen", {
  group = augroup("TermEscToNormal", { clear = true }),
  callback = function(args)
    vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], { buffer = args.buf, desc = "Salir a modo normal" })
    vim.keymap.set("t", "<C-q>", [[<C-\><C-n>]], { buffer = args.buf, desc = "Salir a modo normal" })
  end,
})

-- Último directorio conocido por buffer de terminal, para no reenviar `cd`
-- de ida y vuelta entre Neovim y la terminal (evita un bucle infinito).
local last_dir = {}

-- Neovim/Explorer -> Terminal: reenvía el cwd a cada terminal abierta
-- (solo si de verdad cambió para esa terminal).
autocmd("DirChanged", {
  group = augroup("SyncTerminalsCwd", { clear = true }),
  callback = function()
    local cwd = vim.fn.getcwd()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].buftype == "terminal" and last_dir[buf] ~= cwd then
        local job = vim.b[buf].terminal_job_id
        if job then
          last_dir[buf] = cwd
          vim.fn.chansend(job, "cd " .. vim.fn.fnameescape(cwd) .. "\n")
        end
      end
    end
  end,
})

-- Terminal -> Neovim/Explorer: sincroniza el cwd de Neovim cuando el shell
-- dentro de una terminal hace `cd`. OSC 7 no sirve para esto: se probó en
-- vivo y TermRequest nunca se dispara para esa secuencia en esta versión de
-- Neovim (solo se dispara para secuencias que esperan respuesta, como OSC
-- 52). En su lugar se lee el cwd real del proceso bash directamente de
-- /proc/<pid>/cwd, cada segundo — no depende de que el shell coopere ni le
-- pisa el PROMPT_COMMAND del usuario.
local function poll_terminal_cwd()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buftype == "terminal" then
      local job = vim.b[buf].terminal_job_id
      local ok, pid = pcall(vim.fn.jobpid, job)
      if job and ok and pid then
        local dir = vim.uv.fs_readlink("/proc/" .. pid .. "/cwd")
        if dir and dir ~= last_dir[buf] and dir ~= vim.fn.getcwd() then
          last_dir[buf] = dir
          vim.schedule(function()
            vim.cmd.cd(dir)
          end)
        end
      end
    end
  end
end

do
  local timer = vim.uv.new_timer()
  timer:start(1000, 1000, vim.schedule_wrap(poll_terminal_cwd))
end

-- Archivos que no son texto (documentos ofimáticos, que además son zips por
-- dentro, e imágenes/binarios) se abren con la app del sistema en vez de
-- cargarlos como buffer de texto — evita el problema de "manifest.xml"
-- mostrando el listado del zip en vez de su contenido real.
local OPEN_EXTERNALLY = {
  "zip", "jar", "xpi", "odt", "ods", "odp", "docx", "xlsx", "pptx", "doc", "xls", "ppt",
  "pdf", "iso",
  "jpg", "jpeg", "png", "gif", "bmp", "webp", "svg",
  "mp3", "mp4", "mov", "avi", "mkv", "wav",
}
local ext_pattern = {}
for _, ext in ipairs(OPEN_EXTERNALLY) do
  table.insert(ext_pattern, "*." .. ext)
end

autocmd("BufReadCmd", {
  group = augroup("OpenExternally", { clear = true }),
  pattern = ext_pattern,
  callback = function(args)
    local path = args.file
    vim.fn.jobstart({ "xdg-open", path }, { detach = true })
    vim.schedule(function()
      vim.notify("Abriendo con la app del sistema: " .. vim.fn.fnamemodify(path, ":t"), vim.log.levels.INFO)
      if vim.api.nvim_buf_is_valid(args.buf) then
        vim.cmd("bwipeout! " .. args.buf)
      end
    end)
  end,
})

-- Si estando parado en el explorador se ejecuta ":e" (recargar), Vim lo
-- trata como un archivo normal y lo vacía, dejando una pestaña rota
-- "NvimTree_1" separada del panel real. Un BufReadCmd no alcanza a
-- prevenirlo (se probó en vivo: el buffer se vacía igual), así que se
-- intercepta directo en la línea de comandos: si escribes ":e" estando en
-- el explorador, se avisa en vez de ejecutarlo.
vim.cmd(
  [[cnoreabbrev <expr> e (&filetype ==# 'NvimTree') ? 'echo "Usa <leader>e o :NvimTreeFocus para el explorador, no :e"' : 'e']]
)

-- Restore cursor position
autocmd("BufReadPost", {
  group = augroup("RestoreCursor", { clear = true }),
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local lcount = vim.api.nvim_buf_line_count(0)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})
