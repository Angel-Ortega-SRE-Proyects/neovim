local h = require("tests.spec_helpers")
local git = require("config.git")
local git_mode = require("config.git_mode")
local git_commit = require("config.git_commit")

local original_cwd = vim.fn.getcwd()

local function outside_repo()
  local dir = h.tempdir()
  vim.cmd("cd " .. dir)
  return dir
end

describe("config.git", function()
  after_each(function()
    vim.cmd("cd " .. original_cwd)
    h.reset_ui()
    h.cleanup()
  end)

  it("in_repo distingue un repositorio de una carpeta común", function()
    vim.cmd("cd " .. h.git_repo())
    assert.is_true(git.in_repo())
    outside_repo()
    assert.is_false(git.in_repo())
  end)

  it("guard ejecuta el comando solo dentro de un repositorio", function()
    vim.cmd("cd " .. h.git_repo())
    vim.g.guard_ran = false
    git.guard("let g:guard_ran = v:true")()
    assert.is_true(vim.g.guard_ran)

    outside_repo()
    vim.g.guard_ran = false
    local messages = h.capture_notify(git.guard("let g:guard_ran = v:true"))
    assert.is_false(vim.g.guard_ran)
    assert.matches("No estás dentro de un repositorio git", messages[1].msg)
  end)

  it("start_watch publica la rama y el resumen de cambios", function()
    local repo = h.git_repo({ ["a.txt"] = { "uno" } })
    vim.cmd("cd " .. repo)
    h.write(repo .. "/a.txt", { "uno", "dos", "tres" })
    git.start_watch()
    assert.is_true(h.wait_for(function() return git.branch() == "main" end))
    assert.is_true(h.wait_for(function() return git.diff_stat() ~= nil end))
    assert.same({ files = 1, add = 2, del = 0 }, git.diff_stat())
  end)

  it("open_commits y open_status avisan fuera de un repositorio", function()
    outside_repo()
    local messages = h.capture_notify(function()
      git.open_commits()
      git.open_status()
    end)
    assert.equals(2, #messages)
  end)

  it("las vistas Diffview reciben q/Esc/<leader>gb para volver", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "DiffviewFiles"
    git.reapply_view_navigation()
    for _, lhs in ipairs({ "q", "<Esc>", " gb" }) do
      local found = false
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
        if map.lhs == lhs then found = true end
      end
      assert.is_true(found, lhs)
    end
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

describe("Git Hub", function()
  git_mode.setup_keymaps()

  after_each(function()
    vim.cmd("cd " .. original_cwd)
    h.reset_ui()
    h.cleanup()
  end)

  local function hub_buf()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buf):match("Git Hub$") then return buf end
    end
  end

  it("registra atajos y comandos", function()
    assert.is_function(vim.fn.maparg(" gg", "n", false, true).callback)
    assert.is_function(vim.fn.maparg(" gc", "n", false, true).callback)
    assert.equals(2, vim.fn.exists(":GitBack"))
    assert.equals(2, vim.fn.exists(":GitBask"))
  end)

  it("avisa fuera de un repositorio en lugar de abrir", function()
    outside_repo()
    local messages = h.capture_notify(git_mode.open)
    assert.matches("No estás dentro de un repositorio Git", messages[1].msg)
    assert.equals(1, #vim.api.nvim_list_tabpages())
  end)

  it("abre una pestaña con el menú de acciones y la reutiliza", function()
    local repo = h.git_repo()
    vim.cmd("cd " .. repo)
    git_mode.open()
    local buf = hub_buf()
    assert.is_not_nil(buf)
    assert.is_true(vim.t.git_hub)
    local lines = h.lines(buf)
    assert.matches("Repositorio: " .. vim.pesc(vim.fn.fnamemodify(repo, ":t")), lines[4])
    assert.matches("Historial de commits", lines[10])
    assert.matches("Cerrar Git Hub", lines[18])
    assert.equals(10, vim.api.nvim_win_get_cursor(0)[1])

    vim.cmd("tabfirst")
    git_mode.open()
    assert.equals(2, #vim.api.nvim_list_tabpages())
    assert.equals(buf, vim.api.nvim_get_current_buf())
  end)

  it("resalta las líneas de ayuda, no una acción", function()
    vim.cmd("cd " .. h.git_repo())
    git_mode.open()
    local buf = vim.api.nvim_get_current_buf()
    local ns = vim.api.nvim_get_namespaces()["git-hub"]
    local comment_rows = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
      if mark[4].hl_group == "Comment" then comment_rows[mark[2] + 1] = true end
    end
    local total = #h.lines(buf)
    assert.is_true(comment_rows[total - 1])
    assert.is_true(comment_rows[total])
    assert.is_nil(comment_rows[17])
  end)

  it("Enter en 'Cerrar Git Hub' y q cierran la pestaña", function()
    vim.cmd("cd " .. h.git_repo())
    git_mode.open()
    vim.api.nvim_win_set_cursor(0, { 18, 0 })
    h.press("<CR>")
    assert.equals(1, #vim.api.nvim_list_tabpages())

    git_mode.open()
    h.press("q")
    assert.equals(1, #vim.api.nvim_list_tabpages())
  end)

  it(":GitBack reabre el menú si la ventana se perdió", function()
    vim.cmd("cd " .. h.git_repo())
    git_mode.open()
    vim.cmd("close")
    vim.cmd("GitBack")
    assert.is_not_nil(hub_buf())
    assert.equals(hub_buf(), vim.api.nvim_get_current_buf())
  end)
end)

describe("editor de commits", function()
  after_each(function()
    vim.cmd("cd " .. original_cwd)
    h.reset_ui()
    h.cleanup()
  end)

  local function silent_open(...)
    local args = vim.F.pack_len(...)
    return h.capture_notify(function() git_commit.open(vim.F.unpack_len(args)) end)
  end

  it("sin cambios avisa y deja el buffer listo para escribir", function()
    local repo = h.git_repo()
    local messages = silent_open(repo)
    assert.equals("gitcommit", vim.bo.filetype)
    assert.equals("No hay cambios para describir", messages[1].msg)
  end)

  it("con cambios staged agrega el contexto del repositorio", function()
    local repo = h.git_repo()
    h.write(repo .. "/nuevo.txt", "x")
    h.git(repo, { "add", "nuevo.txt" })
    silent_open(repo)
    local lines = h.lines(0)
    assert.matches("^# Repositorio:", lines[1])
    assert.is_not_nil(h.find_line(0, "Hay cambios staged listos para commit"))
  end)

  it("guardar crea el commit ignorando comentarios y llama on_success", function()
    local repo = h.git_repo()
    h.write(repo .. "/nuevo.txt", "x")
    h.git(repo, { "add", "nuevo.txt" })
    local succeeded = false
    silent_open(repo, function() succeeded = true end)
    vim.cmd("stopinsert")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# comentario", "feat(test): agrega nuevo" })
    h.capture_notify(function() vim.cmd("write") end)
    assert.is_true(h.wait_for(function() return succeeded end))
    assert.equals("feat(test): agrega nuevo", vim.trim(h.git(repo, { "log", "-1", "--format=%s" })))
  end)

  it("guardar sin mensaje no crea commit", function()
    local repo = h.git_repo()
    silent_open(repo)
    vim.cmd("stopinsert")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# solo comentarios" })
    local messages = h.capture_notify(function() vim.cmd("write") end)
    assert.equals("El commit necesita un mensaje", messages[1].msg)
    assert.equals("chore: inicio", vim.trim(h.git(repo, { "log", "-1", "--format=%s" })))
  end)

  it("cancelar con q restaura el buffer previo de la ventana destino", function()
    local repo = h.git_repo()
    local previous = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()
    local cancelled = false
    silent_open(repo, nil, win, function() cancelled = true end)
    local commit_buf = vim.api.nvim_get_current_buf()
    assert.are_not.equal(previous, commit_buf)
    assert.matches("COMMIT", vim.wo[win].winbar)
    vim.cmd("stopinsert")
    h.press("q")
    assert.is_true(cancelled)
    assert.equals(previous, vim.api.nvim_win_get_buf(win))
    assert.equals("", vim.wo[win].winbar)
  end)
end)
