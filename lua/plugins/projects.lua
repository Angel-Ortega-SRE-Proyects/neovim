-- Acceso rápido a carpetas, como el "Open Recent" de VSCode: picker de
-- Telescope con las carpetas que visitaste (se registran solas al cambiar
-- de cwd, ver lua/config/projects.lua), más una opción para agregar
-- cualquier otra a mano. Al elegir una: abre una pestaña propia con cwd
-- local (:tcd), para que cada proyecto conserve su ruta independiente y
-- nvim-tree use esa raíz (sync_root_with_cwd, ver lua/plugins/explorer.lua).
--
-- Uso:
--   <leader>p / <leader>fp / :Projects   picker de carpetas recientes
--   dentro del picker: Enter = ir, <C-a> = agregar carpeta nueva a mano,
--   <C-r> = ponerle un nombre propio (ej. "API backend" en vez de la ruta
--   completa), <C-x> = sacarla de la lista (no borra la carpeta, solo el
--   recuerdo)

local function open_project_tab(path)
  vim.cmd("tabnew")
  vim.cmd.tcd(vim.fn.fnameescape(path))
  require("config.projects").record(path)
  vim.cmd("NvimTreeOpen")
end

local function add_project_prompt(reopen)
  vim.ui.input({ prompt = "Carpeta a agregar: ", completion = "dir", default = vim.fn.getcwd() .. "/" }, function(input)
    if not input or input == "" then
      return
    end
    if vim.fn.isdirectory(input) ~= 1 then
      vim.notify("No es una carpeta: " .. input, vim.log.levels.WARN)
      return
    end
    require("config.projects").record(input)
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
  local projects = require("config.projects")

  local cwd = vim.fn.getcwd()

  pickers.new({}, {
    prompt_title = "Carpetas recientes (Enter: abrir pestaña, <C-a>: agregar, <C-r>: renombrar, <C-x>: quitar)",
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
          projects.rename(entry.path, input)
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

vim.api.nvim_create_user_command("Projects", open_projects_picker, { desc = "Carpetas recientes (como Open Recent de VSCode)" })
vim.cmd("cnoreabbrev projects Projects")
vim.keymap.set("n", "<leader>p", open_projects_picker, { desc = "Abrir proyecto en una pestaña nueva" })
vim.keymap.set("n", "<leader>fp", open_projects_picker, { desc = "Carpetas recientes (como Open Recent de VSCode)" })

return {}
