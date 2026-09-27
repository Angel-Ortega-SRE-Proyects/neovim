local M = {}

local function valid_buffer(buf)
  return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end

local function open_commit_for_buffer(buf)
  local file_lines = vim.b[buf].agent_hub_changed_files
  local candidate = type(file_lines) == "table" and file_lines[vim.fn.line(".")] or nil
  local root = type(candidate) == "table" and type(candidate.root) == "string"
      and candidate.root or vim.fn.getcwd()
  require("config.git_commit").open(root)
end

function M.apply()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if valid_buffer(buf) and vim.api.nvim_buf_get_name(buf):match("Agent Changes") then
      vim.keymap.set("n", "c", function()
        if not valid_buffer(buf) then return end
        open_commit_for_buffer(buf)
      end, { buffer = buf, desc = "Crear commit con Copilot", nowait = true, silent = true })
    end
  end
end

return M
