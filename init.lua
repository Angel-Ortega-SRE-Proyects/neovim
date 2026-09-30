vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Vim intenta "navegar" dentro de .zip/.jar/.odt/.ods/.xlsx (son zips por
-- dentro) como si fueran texto, mezclando el listado del archivo con
-- contenido roto. Se desactiva esa navegación nativa; ver
-- lua/config/autocmds.lua para que en su lugar se abran con la app del
-- sistema.
vim.g.loaded_zipPlugin = 1
vim.g.loaded_tarPlugin = 1

local i18n = require("config.i18n")
require("config.options")
package.loaded["config.keymaps"] = nil
local keymaps = require("config.keymaps")
keymaps.setup_window_navigation()
keymaps.setup_format_menu()
keymaps.setup_explorer_navigation()
local ok_which_key, which_key = pcall(require, "which-key")
if ok_which_key then
  which_key.add({
    { "<leader>s", hidden = true },
    { "<leader>S", hidden = true },
  })
end
require("config.project_settings").setup()
package.loaded["config.buffers"] = nil
require("config.buffers").setup()
require("config.autocmds")
require("config.theme")
require("config.dashboard").setup()
require("config.statusline").setup()
require("config.topline").setup()
require("config.lazy")
require("config.explorer").apply()
package.loaded["config.git_mode"] = nil
package.loaded["config.git_commit"] = nil
require("config.git_mode").setup_keymaps()
require("config.alerts").setup()

local function load_extensions()
  if not require("config.integrations").enabled("extensions") then return end
  local extension_file = vim.fn.stdpath("config") .. "/lua/extensions/init.lua"
  if vim.fn.filereadable(extension_file) == 1 then
    -- Cargar por ruta absoluta permite que :ConfigReload detecte módulos
    -- creados después de arrancar Neovim, incluso con vim.loader activo.
    package.loaded["extensions"] = nil
    local loader, err = loadfile(extension_file)
    if not loader then error(err) end
    local extensions = loader()
    package.loaded["extensions"] = extensions
    extensions.load()
    return
  end

  local ok, extensions = pcall(require, "extensions")
  if ok and type(extensions.load) == "function" then extensions.load() end
end

load_extensions()

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
  package.loaded["config.git"] = nil
  require("config.git").reapply_view_navigation()
  reload_theme_module().reload()
  local wk_ok, wk_plugin = pcall(require, "plugins.which-key")
  if wk_ok and type(wk_plugin.refresh_i18n) == "function" then wk_plugin.refresh_i18n() end
  require("config.buffers").reapply()
  -- render-markdown recibe opts una sola vez (lazy.nvim); se re-evalúa el
  -- spec desde disco y se vuelve a llamar su config para aplicar los cambios.
  package.loaded["plugins.markdown"] = nil
  local md_ok, md_spec = pcall(require, "plugins.markdown")
  local rm = md_ok and md_spec[1]
  if rm and package.loaded["render-markdown"] then
    pcall(rm.config, nil, rm.opts)
    pcall(vim.cmd, "RenderMarkdown disable")
    pcall(vim.cmd, "RenderMarkdown enable")
  end
  vim.api.nvim_echo({
    { i18n.t("Configuración recargada: "), "Normal" },
    { config_file, "String" },
  }, false, {})
end, {
  desc = i18n.t("Recargar la configuración de Neovim"),
  force = true,
})
