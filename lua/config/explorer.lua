local M = {}

local GIT_GLYPHS = {
  unstaged = "M",
  staged = "M",
  unmerged = "M",
  renamed = "R",
  untracked = "?",
  deleted = "D",
  ignored = "",
}

function M.apply()
  local ok, config = pcall(require, "nvim-tree.config")
  if not ok or type(config.g) ~= "table" then
    return
  end

  local glyphs = config.g.renderer.icons.glyphs.git
  for status, glyph in pairs(GIT_GLYPHS) do
    glyphs[status] = glyph
  end

  local api_ok, api = pcall(require, "nvim-tree.api")
  if api_ok then
    pcall(api.tree.reload)
  end
end

return M
