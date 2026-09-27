return {
  "nvim-telescope/telescope.nvim",
  branch = "0.1.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
  },
  cmd = { "Telescope", "Gc", "Gb", "Gs" },
  keys = {
    { "<C-f>", "<cmd>Telescope find_files<CR>", mode = "n", desc = "Buscar y abrir archivos" },
    { "<leader>ff", "<cmd>Telescope find_files<CR>", desc = "Find files" },
    { "<leader>fg", "<cmd>Telescope live_grep<CR>", desc = "Live grep (toda la carpeta actual)" },
    { "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "Buffers" },
    { "<leader>fo", "<cmd>Telescope oldfiles<CR>", desc = "Recent files" },
    {
      "<leader>fs",
      "<cmd>Telescope current_buffer_fuzzy_find<CR>",
      desc = "Buscar SOLO en el archivo abierto",
    },
  },
  config = function()
    local telescope = require("telescope")
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    local function open_selected(prompt_bufnr, command)
      local picker = action_state.get_current_picker(prompt_bufnr)
      local entries = picker:get_multi_selection()
      if #entries == 0 then
        entries = { action_state.get_selected_entry() }
      end
      actions.close(prompt_bufnr)
      vim.schedule(function()
        for _, entry in ipairs(entries) do
          local path = entry.path or entry.filename or entry.value
          if type(path) == "table" then
            path = path.path or path.filename or path.value
          end
          if path and path ~= "" then
            local ok, err = pcall(vim.cmd, { cmd = command, args = { path } })
            if not ok then
              vim.notify("No se pudo abrir " .. path .. ": " .. err, vim.log.levels.ERROR)
            end
          end
        end
      end)
    end

    telescope.setup({
      defaults = {
        layout_strategy = "vertical",
        sorting_strategy = "ascending",
        layout_config = {
          height = 0.82,
          width = 0.88,
          prompt_position = "top",
          preview_cutoff = 100,
        },
        borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
        mappings = {
          i = {
            ["<C-v>"] = function(prompt_bufnr) open_selected(prompt_bufnr, "vsplit") end,
            ["<C-x>"] = function(prompt_bufnr) open_selected(prompt_bufnr, "split") end,
            ["<C-t>"] = actions.select_tab,
          },
          n = {
            ["<C-v>"] = function(prompt_bufnr) open_selected(prompt_bufnr, "vsplit") end,
            ["<C-x>"] = function(prompt_bufnr) open_selected(prompt_bufnr, "split") end,
            ["<C-t>"] = actions.select_tab,
          },
        },
      },
    })
    pcall(telescope.load_extension, "fzf")

    -- Alias de comandos Ex cortos para gc/gs/gb, igual que :DiffviewOpen y
    -- :DiffviewFileHistory ya cubren gd/gh (ver lua/plugins/diffview.lua).
    -- Evita el E492 de escribir ":gb" pensando que existe como tal.
    local git = require("config.git")
    vim.api.nvim_create_user_command("Gc", git.open_commits, {})
    vim.api.nvim_create_user_command("Gb", git.guard("Telescope git_branches"), {})
    vim.api.nvim_create_user_command("Gs", git.open_status, {})
  end,
}
