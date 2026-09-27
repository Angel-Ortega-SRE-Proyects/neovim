vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Vim intenta "navegar" dentro de .zip/.jar/.odt/.ods/.xlsx (son zips por
-- dentro) como si fueran texto, mezclando el listado del archivo con
-- contenido roto. Se desactiva esa navegación nativa; ver
-- lua/config/autocmds.lua para que en su lugar se abran con la app del
-- sistema.
vim.g.loaded_zipPlugin = 1
vim.g.loaded_tarPlugin = 1

require("config.options")
require("config.keymaps")
require("config.project_settings").setup()
require("config.buffers").setup()
require("config.autocmds")
require("config.theme")
require("config.dashboard").setup()
require("config.statusline").setup()
require("config.topline").setup()
require("config.lazy")
package.loaded["config.git_mode"] = nil
package.loaded["config.git_commit"] = nil
require("config.git_mode").setup_keymaps()
require("config.alerts").setup()

local function reload_theme_module()
  local current = package.loaded["config.theme"]
  package.loaded["config.theme"] = nil
  local refreshed = require("config.theme")
  if type(current) ~= "table" then
    return refreshed
  end

  local colors = current.colors
  for key in pairs(colors) do
    colors[key] = nil
  end
  for key, value in pairs(refreshed.colors) do
    colors[key] = value
  end
  refreshed.colors = colors
  current.active = refreshed.active
  package.loaded["config.theme"] = refreshed
  return refreshed
end

local function cleanup_agent_hub_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    local is_hub_buffer = name:match("Agent Changes") or name:match("Agent Hub")
    if name:match("Agent Changes") then
      if type(vim.b[buf].agent_hub_changed_files) ~= "table" then
        vim.b[buf].agent_hub_changed_files = {}
      end
      if type(vim.b[buf].agent_hub_change_folders) ~= "table" then
        vim.b[buf].agent_hub_change_folders = {}
      end
    end
    if is_hub_buffer and #vim.fn.win_findbuf(buf) == 0 then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

vim.api.nvim_create_user_command("ConfigReload", function()
  cleanup_agent_hub_buffers()
  local config_file = vim.fn.stdpath("config") .. "/init.lua"
  vim.cmd("source " .. vim.fn.fnameescape(config_file))
  cleanup_agent_hub_buffers()
  package.loaded["config.agent_hub_reload"] = nil
  require("config.agent_hub_reload").apply()
  reload_theme_module().reload()
  vim.api.nvim_echo({
    { "Configuración recargada: ", "Normal" },
    { config_file, "String" },
  }, false, {})
end, {
  desc = "Recargar la configuración de Neovim",
  force = true,
})
