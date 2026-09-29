local h = require("tests.spec_helpers")

require("config.options")
require("config.keymaps")
require("config.autocmds")
require("config.buffers").setup()
require("config.project_settings").setup()

describe("opciones del editor", function()
  it("fija indentación, búsqueda y archivos persistentes", function()
    assert.is_true(vim.o.number)
    assert.is_false(vim.o.relativenumber)
    assert.is_true(vim.o.expandtab)
    assert.equals(2, vim.o.shiftwidth)
    assert.equals(2, vim.o.tabstop)
    assert.is_true(vim.o.ignorecase)
    assert.is_true(vim.o.smartcase)
    assert.equals(3, vim.o.laststatus)
    assert.is_true(vim.o.undofile)
    assert.is_true(vim.o.exrc)
    assert.is_true(vim.o.secure)
    assert.equals("unnamedplus", vim.o.clipboard)
    assert.equals(1, vim.fn.isdirectory(vim.fn.stdpath("state") .. "/undo"))
    assert.equals(1, vim.fn.isdirectory(vim.fn.stdpath("state") .. "/swap"))
  end)
end)

describe("atajos globales", function()
  local function rhs(lhs, mode)
    return vim.fn.maparg(lhs, mode or "n", false, true)
  end

  it("define navegación de buffers, guardado y edición visual", function()
    assert.equals(":bprevious<CR>", rhs("<S-H>").rhs)
    assert.equals(":bnext<CR>", rhs("<S-L>").rhs)
    assert.equals(":update<CR>", rhs("<C-S>").rhs)
    assert.equals("<C-o>:update<CR>", rhs("<C-S>", "i").rhs)
    assert.equals("<gv", rhs("<", "v").rhs)
    assert.equals(">gv", rhs(">", "v").rhs)
    assert.equals("<cmd>ThemeSelect<CR>", rhs(" uc").rhs)
    assert.equals("<C-c>", rhs("<Esc>", "c").rhs)
  end)

  it("<leader>aq avisa cuando AgentHub no está abierto", function()
    local messages = h.capture_notify(function() rhs(" aq").callback() end)
    assert.equals("AgentHub no está abierto", messages[1].msg)
  end)

  it("<leader>aq cierra la pestaña del AgentHub", function()
    h.reset_ui()
    vim.cmd("tabnew")
    vim.api.nvim_tabpage_set_var(0, "agent_hub", true)
    assert.equals(2, #vim.api.nvim_list_tabpages())
    rhs(" aq").callback()
    assert.equals(1, #vim.api.nvim_list_tabpages())
  end)
end)

describe("autocomandos", function()
  after_each(function()
    h.reset_ui()
    h.cleanup()
  end)

  it("elimina espacios finales al guardar", function()
    local path = h.tempdir() .. "/trim.txt"
    vim.cmd("edit " .. path)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hola   ", "mundo\t" })
    vim.cmd("write")
    assert.same({ "hola", "mundo" }, vim.fn.readfile(path))
  end)

  it("restaura la posición del cursor al reabrir", function()
    local path = h.tempdir() .. "/cursor.txt"
    h.write(path, { "uno", "dos", "tres" })
    vim.cmd("edit " .. path)
    vim.api.nvim_buf_set_mark(0, '"', 3, 1, {})
    vim.api.nvim_exec_autocmds("BufReadPost", { buffer = 0 })
    assert.equals(3, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("abre binarios y documentos con la app del sistema", function()
    local autocmds = vim.api.nvim_get_autocmds({ group = "OpenExternally", event = "BufReadCmd" })
    local patterns = vim.tbl_map(function(autocmd) return autocmd.pattern end, autocmds)
    for _, pattern in ipairs({ "*.pdf", "*.zip", "*.png", "*.docx", "*.mp4" }) do
      assert.is_true(vim.tbl_contains(patterns, pattern), pattern)
    end
  end)

  it("quita números y signcolumn en terminales y mapea <C-q>", function()
    vim.cmd("terminal")
    assert.is_false(vim.wo.number)
    assert.equals("no", vim.wo.signcolumn)
    assert.equals("<C-\\><C-n>", vim.fn.maparg("<C-Q>", "t", false, true).rhs)
    vim.fn.jobstop(vim.b.terminal_job_id)
  end)

  it("registra los grupos de diagnóstico y sincronización de cwd", function()
    for _, group in ipairs({ "HighlightYank", "DiagnosticHover", "SyncTerminalsCwd", "RestoreCursor" }) do
      assert.is_true(#vim.api.nvim_get_autocmds({ group = group }) > 0, group)
    end
  end)
end)

describe("perfiles de buffer", function()
  after_each(h.reset_ui)

  local function with_filetype(filetype)
    vim.cmd("enew")
    vim.bo.filetype = filetype
  end

  it("markdown activa wrap, spell y textwidth 100", function()
    with_filetype("markdown")
    assert.is_true(vim.wo.wrap)
    assert.is_true(vim.wo.spell)
    assert.equals(100, vim.bo.textwidth)
  end)

  it("gitcommit usa textwidth 72", function()
    with_filetype("gitcommit")
    assert.equals(72, vim.bo.textwidth)
    assert.is_true(vim.wo.spell)
  end)

  it("código desactiva wrap y spell y guarda la raíz del proyecto", function()
    vim.g.project_root = "/tmp/proyecto"
    with_filetype("lua")
    assert.is_false(vim.wo.wrap)
    assert.is_false(vim.wo.spell)
    assert.equals("/tmp/proyecto", vim.b.project_root)
  end)
end)

describe("contexto de proyecto", function()
  it("refresh publica la raíz y dispara User ProjectChanged", function()
    local received
    local id = vim.api.nvim_create_autocmd("User", {
      pattern = "ProjectChanged",
      callback = function(args) received = args.data.root end,
    })
    require("config.project_settings").refresh()
    vim.api.nvim_del_autocmd(id)
    assert.equals(vim.fn.getcwd(), vim.g.project_root)
    assert.equals(vim.fn.getcwd(), received)
  end)
end)
