local M = {}

function M.options()
  return {
    messages = {
      view = "notify",
      view_error = "notify",
      view_warn = "notify",
    },
    views = {
      notify = {
        backend = "popup",
        relative = "editor",
        position = { row = -2, col = "100%" },
        size = { width = 64, height = "auto", max_height = 8 },
        enter = false,
        timeout = 6000,
        border = { style = "rounded", padding = { 1, 2 } },
        win_options = {
          wrap = true,
          linebreak = true,
          winhighlight = { Normal = "NoiceNotify", FloatBorder = "NoiceNotifyBorder" },
        },
      },
    },
  }
end

function M.apply_highlights()
  local colors = require("config.theme").colors
  vim.api.nvim_set_hl(0, "NoiceNotify", { bg = colors.bg_alt, fg = colors.fg })
  vim.api.nvim_set_hl(0, "NoiceNotifyBorder", { bg = colors.bg_alt, fg = colors.warn, bold = true })
end

function M.setup()
  local ok, noice = pcall(require, "noice")
  if not ok then return end
  noice.setup(M.options())
  M.apply_highlights()
end

return M
