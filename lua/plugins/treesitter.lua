local ensure_installed = {
  "lua", "vim", "vimdoc", "query",
  "bash", "markdown", "markdown_inline",
  -- YAML/JSON + devops
  "json", "yaml", "toml", "hcl", "dockerfile", "gitignore",
  -- Lenguajes de propósito general
  "python", "javascript", "typescript", "tsx", "go", "gomod", "gowork",
  "java", "c_sharp",
}

return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  build = ":TSUpdate",
  lazy = false,
  config = function()
    require("nvim-treesitter").install(ensure_installed)

    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("TreesitterStart", { clear = true }),
      callback = function(args)
        local ok = pcall(vim.treesitter.start, args.buf)
        if ok then
          vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
      end,
    })
  end,
}
