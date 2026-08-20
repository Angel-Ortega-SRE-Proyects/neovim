return {
  "nvim-telescope/telescope.nvim",
  branch = "0.1.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
  },
  cmd = { "Telescope", "Gc", "Gb", "Gs" },
  keys = {
    { "<leader>ff", "<cmd>Telescope find_files<CR>", desc = "Find files" },
    { "<leader>fg", "<cmd>Telescope live_grep<CR>", desc = "Live grep (toda la carpeta actual)" },
    { "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "Buffers" },
    { "<leader>fh", "<cmd>Telescope help_tags<CR>", desc = "Help tags" },
    { "<leader>fo", "<cmd>Telescope oldfiles<CR>", desc = "Recent files" },
    {
      "<leader>fs",
      "<cmd>Telescope current_buffer_fuzzy_find<CR>",
      desc = "Buscar SOLO en el archivo abierto",
    },
    {
      "<leader>fO",
      "<cmd>Telescope grep_open_files<CR>",
      desc = "Buscar en todos los archivos abiertos (buffers)",
    },
    {
      "<leader>fd",
      function()
        vim.ui.input({ prompt = "Buscar en carpeta: ", completion = "dir", default = vim.fn.getcwd() .. "/" }, function(dir)
          if dir and dir ~= "" then
            require("telescope.builtin").live_grep({ search_dirs = { dir } })
          end
        end)
      end,
      desc = "Buscar en UNA carpeta específica",
    },
    { "<leader>gc", function() require("config.git").open_commits() end, desc = "Git commits (Enter: ver diff)" },
    { "<leader>gb", function() require("config.git").guard("Telescope git_branches")() end, desc = "Git branches" },
    { "<leader>gs", function() require("config.git").open_status() end, desc = "Git status (Enter: diff, C-e: abrir archivo)" },
  },
  config = function()
    local telescope = require("telescope")
    telescope.setup({
      defaults = {
        mappings = {},
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
