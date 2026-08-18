local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

-- Highlight on yank
autocmd("TextYankPost", {
  group = augroup("HighlightYank", { clear = true }),
  callback = function()
    vim.highlight.on_yank({ timeout = 150 })
  end,
})

-- Trim trailing whitespace on save
autocmd("BufWritePre", {
  group = augroup("TrimWhitespace", { clear = true }),
  pattern = "*",
  command = [[%s/\s\+$//e]],
})

-- Terminal <-> Neovim/Explorer cwd sync, para cualquier buffer de terminal
-- (:Tf flotante de toggleterm, :Term como pestaña, o un :terminal a pelo).
local OSC7_HOOK = [[PROMPT_COMMAND='printf "\033]7;file://%s\a" "$PWD"'; clear]]

autocmd("TermOpen", {
  group = augroup("TermOsc7Hook", { clear = true }),
  callback = function(args)
    vim.defer_fn(function()
      local job = vim.b[args.buf].terminal_job_id
      if job then
        vim.fn.chansend(job, OSC7_HOOK .. "\n")
      end
    end, 50)
  end,
})

-- Neovim/Explorer -> Terminal: reenvía el cwd a cada terminal abierta.
autocmd("DirChanged", {
  group = augroup("SyncTerminalsCwd", { clear = true }),
  callback = function()
    local cwd = vim.fn.getcwd()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].buftype == "terminal" then
        local job = vim.b[buf].terminal_job_id
        if job then
          vim.fn.chansend(job, "cd " .. vim.fn.fnameescape(cwd) .. "\n")
        end
      end
    end
  end,
})

-- Sync Neovim's cwd when the shell inside a terminal buffer cd's elsewhere
-- (shell reports its cwd via OSC 7). nvim-tree follows automatically via
-- DirChanged.
autocmd("TermRequest", {
  group = augroup("TermOsc7Sync", { clear = true }),
  callback = function(args)
    local seq = args.data and args.data.sequence or ""
    local dir = seq:match("\027%]7;file://[^/]*(/[^\027\a]*)")
    if not dir then
      return
    end
    local ok, decoded = pcall(vim.uri_decode, dir)
    dir = ok and decoded or dir
    if vim.fn.isdirectory(dir) == 1 and dir ~= vim.fn.getcwd() then
      -- TermRequest se dispara en un contexto restringido: si se hace :cd
      -- aquí mismo, el DirChanged resultante no llega bien a nvim-tree.
      vim.schedule(function()
        vim.cmd.cd(dir)
      end)
    end
  end,
})

-- Restore cursor position
autocmd("BufReadPost", {
  group = augroup("RestoreCursor", { clear = true }),
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local lcount = vim.api.nvim_buf_line_count(0)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})
