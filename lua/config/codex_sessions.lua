local M = {}

local function session_root()
  return vim.fn.expand("~/.codex/sessions")
end

local function compact_title(text, fallback)
  text = vim.trim((text or ""):gsub("%s+", " "))
  if text == "" then return fallback end
  if #text > 52 then
    return text:sub(1, 49) .. "..."
  end
  return text
end

local function first_user_text(payload)
  if payload.role ~= "user" or type(payload.content) ~= "table" then
    return nil
  end
  for _, item in ipairs(payload.content) do
    if item.type == "input_text" and item.text then
      local text = item.text
      if text:match("^# AGENTS%.md") or text:match("^<INSTRUCTIONS>")
          or text:match("^╔─ HIGPERTEXT") or text:match("^<image name=") then
        return nil
      end
      return text
    end
  end
  return nil
end

local function is_interactive(metadata)
  if metadata.thread_source == "guardian_review" or metadata.thread_source == "subagent" then
    return false
  end
  if type(metadata.source) == "table" then
    return metadata.source.subagent == nil
  end
  return metadata.source ~= "subagent"
end

local function read_metadata(path, stat)
  local file = io.open(path, "r")
  if not file then return nil end

  local metadata, title
  for line in file:lines() do
    local ok, entry = pcall(vim.json.decode, line)
    if ok and type(entry) == "table" then
      if entry.type == "session_meta" then
        metadata = entry.payload
      elseif entry.type == "response_item" and entry.payload then
        title = title or first_user_text(entry.payload)
      end
    end
    if metadata and title then break end
  end
  file:close()

  if not metadata or not metadata.id or not metadata.cwd or not is_interactive(metadata) then
    return nil
  end

  local short_id = metadata.id:sub(-8)
  local fallback = "sesión " .. short_id
  local label = "Codex · " .. compact_title(title, fallback)
  local cwd = vim.fn.fnamemodify(metadata.cwd, ":p")
  if cwd ~= "/" then cwd = cwd:gsub("/$", "") end

  return {
    name = label .. " [" .. short_id .. "]",
    cmd = { "codex", "resume", metadata.id },
    cwd = cwd,
    action = "agent",
    external = true,
    session_id = metadata.id,
    updated_at = stat.mtime.sec,
  }
end

local function scan_directory(path, sessions)
  local handle = vim.uv.fs_scandir(path)
  if not handle then return end
  while true do
    local name, kind = vim.uv.fs_scandir_next(handle)
    if not name then break end
    local child = path .. "/" .. name
    if kind == "directory" then
      scan_directory(child, sessions)
    elseif kind == "file" and name:match("%.jsonl$") then
      local stat = vim.uv.fs_stat(child)
      if stat then
        local session = read_metadata(child, stat)
        if session then table.insert(sessions, session) end
      end
    end
  end
end

function M.list()
  local root = session_root()
  if vim.fn.isdirectory(root) ~= 1 then return {} end

  local sessions = {}
  scan_directory(root, sessions)
  table.sort(sessions, function(left, right)
    return left.updated_at > right.updated_at
  end)
  return sessions
end

function M.grouped()
  local projects = require("config.projects")
  local by_path = {}
  for _, session in ipairs(M.list()) do
    local group = by_path[session.cwd]
    if not group then
      group = {
        path = session.cwd,
        name = projects.name_for(session.cwd),
        sessions = {},
        updated_at = session.updated_at,
      }
      by_path[session.cwd] = group
    end
    table.insert(group.sessions, session)
    group.updated_at = math.max(group.updated_at, session.updated_at)
  end

  local groups = {}
  for _, group in pairs(by_path) do
    table.sort(group.sessions, function(left, right)
      return left.updated_at > right.updated_at
    end)
    table.insert(groups, group)
  end
  table.sort(groups, function(left, right)
    return left.updated_at > right.updated_at
  end)
  return groups
end

return M
