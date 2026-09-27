-- Acceso rápido a carpetas, como el "Open Recent" de VSCode: picker de
-- Telescope con las carpetas que visitaste (se registran solas al cambiar
-- de cwd, ver lua/config/projects.lua), más una opción para agregar
-- cualquier otra a mano. Al elegir una: abre una pestaña propia con cwd
-- local (:tcd), para que cada proyecto conserve su ruta independiente y
-- nvim-tree use esa raíz (sync_root_with_cwd, ver lua/plugins/explorer.lua).
--
-- Uso:
--   <leader>p / :Projects   picker de carpetas recientes
--   <leader>pn / :ProjectNew [ruta]       crear y abrir un proyecto
--   :ProjectRename [nombre]               nombrar el proyecto actual
--   dentro del picker: Enter = ir, <C-a> = agregar carpeta nueva a mano,
--   <C-r> = ponerle un nombre propio (ej. "API backend" en vez de la ruta
--   completa), <C-x> = sacarla de la lista (no borra la carpeta, solo el
--   recuerdo)

local projects = require("config.projects")

local function open_project_tab(path)
  projects.open(path)
end

local function valid_project_path(path)
  if vim.fn.isdirectory(path) == 1 then
    return true
  end
  vim.notify("No es una carpeta: " .. path, vim.log.levels.WARN)
  return false
end

local function finish_new_project(path, name)
  if not valid_project_path(path) then
    return
  end
  local abs = vim.fn.fnamemodify(path, ":p"):gsub("/$", "")
  projects.record(abs)
  projects.rename(abs, vim.trim(name or ""))
  open_project_tab(abs)
end

local function prompt_new_project(path)
  local function prompt_name(selected_path)
    vim.ui.input({ prompt = "Nombre del proyecto (vacío = nombre de carpeta): " }, function(name)
      if name ~= nil then
        finish_new_project(selected_path, name)
      end
    end)
  end
  if path and path ~= "" then
    prompt_name(path)
    return
  end
  vim.ui.input({ prompt = "Carpeta del proyecto: ", completion = "dir", default = vim.fn.getcwd() .. "/" }, function(input)
    if input and input ~= "" then
      prompt_name(input)
    end
  end)
end

local function add_project_prompt(reopen)
  vim.ui.input({ prompt = "Carpeta a agregar: ", completion = "dir", default = vim.fn.getcwd() .. "/" }, function(input)
    if not input or input == "" then
      return
    end
    if not valid_project_path(input) then
      return
    end
    projects.record(input)
    if reopen then
      reopen()
    end
  end)
end

local function open_projects_picker()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local cwd = vim.fn.getcwd()

  pickers.new({}, {
    prompt_title = "Proyectos (Enter: abrir, <C-n>: nuevo, <C-a>: agregar, <C-r>: nombrar, <C-x>: quitar)",
    finder = finders.new_table({
      results = projects.list(),
      entry_maker = function(entry)
        local marker = entry.path == cwd and "● " or "  "
        local label = entry.name or vim.fn.fnamemodify(entry.path, ":~")
        local display = entry.name
          and string.format("%s%s  %s", marker, label, vim.fn.fnamemodify(entry.path, ":~"))
          or (marker .. label)
        return {
          value = entry,
          display = display,
          ordinal = label .. " " .. entry.path,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selected = action_state.get_selected_entry()
        if not selected then
          return
        end
        actions.close(prompt_bufnr)
        open_project_tab(selected.value.path)
      end)
      map({ "i", "n" }, "<C-a>", function()
        actions.close(prompt_bufnr)
        add_project_prompt(open_projects_picker)
      end)
      map({ "i", "n" }, "<C-n>", function()
        actions.close(prompt_bufnr)
        prompt_new_project()
      end)
      map({ "i", "n" }, "<C-r>", function()
        local selected = action_state.get_selected_entry()
        if not selected then
          return
        end
        local entry = selected.value
        actions.close(prompt_bufnr)
        vim.ui.input({
          prompt = "Nombre para " .. entry.path .. " (vacío = sacar el nombre): ",
          default = entry.name or "",
        }, function(input)
          if input == nil then
            return
          end
          projects.rename(entry.path, vim.trim(input))
          open_projects_picker()
        end)
      end)
      map({ "i", "n" }, "<C-x>", function()
        local selected = action_state.get_selected_entry()
        if not selected then
          return
        end
        projects.remove(selected.value.path)
        actions.close(prompt_bufnr)
        open_projects_picker()
      end)
      return true
    end,
  }):find()
end

-- NO se redeclara el spec de "nvim-telescope/telescope.nvim" acá (eso ya
-- vive en lua/plugins/telescope.lua, con su propio `config` que hace el
-- setup real + la extensión fzf): un segundo `config` para el mismo plugin
-- pisaría a ese en vez de sumarse, y telescope.nvim carga solo con `require`
-- gracias al loader de lazy.nvim aunque este archivo no lo declare.
require("config.projects").start_watch()

vim.api.nvim_create_user_command("Projects", open_projects_picker, { desc = "Elegir proyecto guardado" })
vim.api.nvim_create_user_command("Project", open_projects_picker, { desc = "Elegir proyecto guardado" })
vim.api.nvim_create_user_command("ProjectNew", function(opts)
  prompt_new_project(opts.args)
end, { nargs = "?", complete = "dir", desc = "Crear y abrir proyecto en pestaña propia" })
vim.api.nvim_create_user_command("ProjectRename", function(opts)
  local path = vim.fn.getcwd()
  projects.record(path)
  local function rename(name)
    if name ~= nil then
      projects.rename(path, vim.trim(name))
    end
  end
  if opts.args ~= "" then
    rename(opts.args)
  else
    vim.ui.input({ prompt = "Nombre del proyecto (vacío = nombre de carpeta): ", default = projects.current_name() or "" }, rename)
  end
end, { nargs = "*", desc = "Asignar un nombre al proyecto actual" })
vim.cmd("cnoreabbrev projects Projects")
vim.keymap.set("n", "<leader>p", open_projects_picker, { desc = "Abrir proyecto en una pestaña nueva" })
vim.keymap.set("n", "<leader>pn", prompt_new_project, { desc = "Crear y abrir proyecto" })
return {}
