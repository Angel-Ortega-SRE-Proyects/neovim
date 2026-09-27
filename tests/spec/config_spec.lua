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

describe("editor de commits", function()
  it("crea un buffer gitcommit cancelable sin colisiones de nombre", function()
    local git_commit = require("config.git_commit")
    local before = #vim.api.nvim_list_bufs()

    git_commit.open(vim.fn.getcwd())
    local first = vim.api.nvim_get_current_buf()
    assert.equals("gitcommit", vim.bo[first].filetype)
    assert.matches("^COMMIT_EDITMSG%-", vim.fn.fnamemodify(vim.api.nvim_buf_get_name(first), ":t"))

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
    local hub_tab
    for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
      local ok, is_agent_hub = pcall(vim.api.nvim_tabpage_get_var, tabpage, "agent_hub")
      if ok and is_agent_hub then hub_tab = tabpage end
    end
    assert.is_truthy(hub_tab)

    local changes_buf
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(hub_tab)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_get_name(buf):match("Agent Changes") then changes_buf = buf end
    end
    assert.is_truthy(changes_buf)
    vim.api.nvim_set_current_tabpage(hub_tab)
    vim.api.nvim_set_current_buf(changes_buf)

    local commit_map = vim.fn.maparg("c", "n", false, true)
    assert.is_function(commit_map.callback)
    commit_map.callback()
    assert.equals("gitcommit", vim.bo[vim.api.nvim_get_current_buf()].filetype)

    vim.cmd("stopinsert")
    local cancel_map = vim.fn.maparg("q", "n", false, true)
    assert.is_function(cancel_map.callback)
    cancel_map.callback()
    vim.api.nvim_set_current_buf(changes_buf)

    local close_map = vim.fn.maparg("q", "n", false, true)
    assert.is_function(close_map.callback)
    close_map.callback()
    for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
      local ok, is_agent_hub = pcall(vim.api.nvim_tabpage_get_var, tabpage, "agent_hub")
      assert.is_false(ok and is_agent_hub)
    end
  end)
end)
