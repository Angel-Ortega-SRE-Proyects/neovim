local function cleanup_buffer(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

describe("configuración Git", function()
  it("expone los atajos principales", function()
    local git_mode = require("config.git_mode")
    git_mode.setup_keymaps()

    local git_map = vim.fn.maparg("<leader>gg", "n", false, true)
    local copilot_map = vim.fn.maparg("<leader>gc", "n", false, true)

    assert.is_function(git_map.callback)
    assert.is_function(copilot_map.callback)
    assert.equals(2, vim.fn.exists(":GitBack"))
    assert.equals(2, vim.fn.exists(":GitBask"))
  end)

  it("registra salida en vistas Diffview", function()
    require("config.git")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "DiffviewFileHistory"
    vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
    local mapping = vim.fn.maparg("q", "n", false, true)
    assert.is_function(mapping.callback)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("abre un Git Hub real con una ventana y buffer válidos", function()
    local git_mode = require("config.git_mode")
    git_mode.open()

    local found = false
    for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
      local ok, is_git_hub = pcall(vim.api.nvim_tabpage_get_var, tabpage, "git_hub")
      if ok and is_git_hub then
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
          local buf = vim.api.nvim_win_get_buf(win)
          if vim.api.nvim_buf_get_name(buf):match("Git Hub$") then
            found = vim.api.nvim_win_is_valid(win)
            break
          end
        end
      end
    end
    assert.is_true(found)
    vim.cmd("tabclose!")
  end)
end)

describe("sesiones Codex", function()
  it("distingue una sesión activa de una tarea ejecutándose", function()
    local sessions = require("config.codex_sessions")
    assert.equals("activo", sessions.status({ active = true }))
    assert.equals("detenido", sessions.status({ active = false }))
  end)
end)

describe("editor de commits", function()
  it("crea un buffer gitcommit cancelable sin colisiones de nombre", function()
    local git_commit = require("config.git_commit")
    local before = #vim.api.nvim_list_bufs()

    git_commit.open(vim.fn.getcwd())
    local first = vim.api.nvim_get_current_buf()
    assert.equals("gitcommit", vim.bo[first].filetype)
    assert.equals("", vim.bo[first].buftype)
    assert.is_true(vim.bo[first].buflisted)
    local commit_lines = vim.api.nvim_buf_get_lines(first, 0, 2, false)
    assert.matches("^# Repositorio:", commit_lines[1])
    assert.matches("^# Ruta:", commit_lines[2])
    local copilot_map = vim.fn.maparg("<C-G>", "n", false, true)
    assert.is_function(copilot_map.callback)
    assert.matches("^COMMIT_EDITMSG%-", vim.fn.fnamemodify(vim.api.nvim_buf_get_name(first), ":t"))
    assert.has_no_error(function()
      vim.api.nvim_exec_autocmds("VimResized", { modeline = false })
      vim.api.nvim_exec_autocmds("WinResized", { modeline = false })
    end)

    vim.cmd("stopinsert")
    vim.api.nvim_feedkeys("q", "xt", false)
    vim.wait(20)
    assert.is_false(vim.api.nvim_buf_is_valid(first))

    git_commit.open(vim.fn.getcwd())
    local second = vim.api.nvim_get_current_buf()
    assert.is_true(vim.api.nvim_buf_is_valid(second))
    assert.is_true(#vim.api.nvim_list_bufs() >= before)
    cleanup_buffer(second)
  end)
end)

describe("AgentHub", function()
  it("carga sin errores y registra el cierre", function()
    local ok, err = pcall(require, "plugins.ai_cli")
    assert.is_true(ok, err)
    assert.equals(2, vim.fn.exists(":AgentHubClose"))
    local mapping = vim.fn.maparg("<leader>aq", "n", false, true)
    assert.is_function(mapping.callback)

    vim.cmd("tabnew")
    local hub_tab = vim.api.nvim_get_current_tabpage()
    vim.api.nvim_tabpage_set_var(hub_tab, "agent_hub", true)
    local tabs_before = #vim.api.nvim_list_tabpages()
    mapping.callback()
    assert.equals(tabs_before - 1, #vim.api.nvim_list_tabpages())
  end)

  it("puede actualizar el atajo de commit sin reiniciar Neovim", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "Agent Changes hot-reload")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { " c commit" })
    vim.b[buf].agent_hub_changed_files = {}

    require("config.agent_hub_reload").apply()
    vim.api.nvim_set_current_buf(buf)
    local mapping = vim.fn.maparg("c", "n", false, true)
    assert.is_function(mapping.callback)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("recorre AgentHub → commit → cancelar → cerrar", function()
    vim.cmd("Agents")
    assert.has_no_error(function()
      require("config.agent_hub_reload").apply()
      vim.api.nvim_exec_autocmds("VimResized", { modeline = false })
      vim.api.nvim_exec_autocmds("WinResized", { modeline = false })
    end)
    local hub_tab
    for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
      local ok, is_agent_hub = pcall(vim.api.nvim_tabpage_get_var, tabpage, "agent_hub")
      if ok and is_agent_hub then hub_tab = tabpage end
    end
    assert.is_truthy(hub_tab)

    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(hub_tab)) do
      local buf = vim.api.nvim_win_get_buf(win)
      assert.not_equals("", vim.api.nvim_buf_get_name(buf))
    end

    local changes_buf
    local sidebar_win
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(hub_tab)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_get_name(buf):match("Agent Changes") then changes_buf = buf end
      if vim.api.nvim_buf_get_name(buf):match("Agent Hub %d+$") then sidebar_win = win end
    end
    assert.is_truthy(changes_buf)
    assert.is_truthy(sidebar_win)
    vim.api.nvim_set_current_tabpage(hub_tab)
    vim.api.nvim_set_current_buf(changes_buf)
    local windows_before_commit = #vim.api.nvim_tabpage_list_wins(hub_tab)

    local commit_map = vim.fn.maparg("c", "n", false, true)
    assert.is_function(commit_map.callback)
    local move_map = vim.fn.maparg("<leader>a<Left>", "n", false, true)
    assert.is_function(move_map.callback)
    local control_map = vim.fn.maparg("<C-@>", "n", false, true)
    assert.is_function(control_map.callback)
    control_map.callback()
    assert.equals("move", vim.b[changes_buf].agent_hub_control_mode)
    vim.fn.maparg("r", "n", false, true).callback()
    assert.equals("resize", vim.b[changes_buf].agent_hub_control_mode)
    vim.fn.maparg("m", "n", false, true).callback()
    assert.equals("move", vim.b[changes_buf].agent_hub_control_mode)
    vim.fn.maparg("<Esc>", "n", false, true).callback()
    assert.is_nil(vim.b[changes_buf].agent_hub_control_mode)

    vim.api.nvim_set_current_win(sidebar_win)
    local sidebar_width = vim.api.nvim_win_get_width(sidebar_win)
    vim.fn.maparg("<C-@>", "n", false, true).callback()
    vim.fn.maparg("r", "n", false, true).callback()
    vim.fn.maparg("<Right>", "n", false, true).callback()
    local resized_width = vim.api.nvim_win_get_width(sidebar_win)
    assert.is_true(resized_width > sidebar_width)
    vim.api.nvim_exec_autocmds("WinResized", { modeline = false })
    assert.equals(resized_width, vim.api.nvim_win_get_width(sidebar_win))
    vim.fn.maparg("<Esc>", "n", false, true).callback()

    commit_map.callback()
    assert.equals("gitcommit", vim.bo[vim.api.nvim_get_current_buf()].filetype)
    assert.equals(windows_before_commit, #vim.api.nvim_tabpage_list_wins(hub_tab))

    vim.cmd("stopinsert")
    local cancel_map = vim.fn.maparg("q", "n", false, true)
    assert.is_function(cancel_map.callback)
    cancel_map.callback()
    vim.api.nvim_set_current_buf(changes_buf)

    local close_map = vim.fn.maparg("q", "n", false, true)
    assert.is_function(close_map.callback)
    close_map.callback()

    vim.cmd("Agents")
    local reopened_sidebar
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_get_name(buf):match("Agent Hub %d+$") then reopened_sidebar = win end
    end
    assert.is_truthy(reopened_sidebar)
    assert.equals(resized_width, vim.api.nvim_win_get_width(reopened_sidebar))
    vim.fn.maparg("q", "n", false, true).callback()

    for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
      local ok, is_agent_hub = pcall(vim.api.nvim_tabpage_get_var, tabpage, "agent_hub")
      assert.is_false(ok and is_agent_hub)
    end
  end)
end)
