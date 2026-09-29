-- Configuración coherente del buffer activo según su tipo de archivo.
-- Los proyectos pueden sobrescribir estos valores desde `.nvim.lua` usando
-- vim.opt_local o creando autocmds específicos para su raíz.
local M = {}

local PROFILES = {
  code = {
    wrap = false,
    spell = false,
    textwidth = 0,
  },
  markdown = {
    wrap = true,
    linebreak = true,
    spell = true,
    textwidth = 100,
  },
  gitcommit = {
    wrap = true,
    spell = true,
    textwidth = 72,
  },
}

local CODE_FILETYPES = {
  bash = true,
  css = true,
  go = true,
  html = true,
  java = true,
  javascript = true,
  json = true,
  lua = true,
  python = true,
  rust = true,
  sh = true,
  terraform = true,
  typescript = true,
  yaml = true,
}

local function profile_for(filetype)
  if filetype == "markdown" or filetype == "markdown_inline" then
    return PROFILES.markdown
  end
  if filetype == "gitcommit" then
    return PROFILES.gitcommit
  end
  if CODE_FILETYPES[filetype] then
    return PROFILES.code
  end
  return nil
end

local function apply_profile(args)
  local profile = profile_for(vim.bo[args.buf].filetype)
  if not profile then
    return
  end
  for option, value in pairs(profile) do
    vim.opt_local[option] = value
  end
  vim.b[args.buf].project_root = vim.g.project_root
end

local function remove_hidden_file_buffer(args)
  local buf = args.buf
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return
  end
  if vim.bo[buf].modified then
    return
  end

  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) == 0 then
      pcall(vim.api.nvim_buf_delete, buf, { force = false })
    end
  end)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("ActiveBufferSettings", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "*",
    callback = apply_profile,
    desc = "Aplicar configuración del buffer activo según su tipo",
  })
  vim.api.nvim_create_autocmd("BufLeave", {
    group = group,
    pattern = "*",
    callback = remove_hidden_file_buffer,
    desc = "No acumular archivos ocultos en una misma ventana",
  })
end

return M
