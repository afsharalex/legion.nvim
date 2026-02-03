--- Git utility functions
-- @module pear.utils.git

local M = {}

--- Find git root for a file path
-- @param filepath string Path to file
-- @return string|nil Git root directory or nil if not in a git repo
function M.find_root(filepath)
  if not filepath or filepath == "" then
    return nil
  end

  local dir = vim.fn.fnamemodify(filepath, ":h")
  local result = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel")

  if vim.v.shell_error == 0 and #result > 0 then
    return result[1]
  end

  return nil
end

--- Get the cwd to use for an operation
-- Returns git root if available, otherwise the file's directory
-- @param filepath string Path to file
-- @return string Working directory
function M.get_cwd(filepath)
  if not filepath or filepath == "" then
    return vim.fn.getcwd()
  end

  local git_root = M.find_root(filepath)
  if git_root then
    return git_root
  end

  -- Fallback to file's directory
  return vim.fn.fnamemodify(filepath, ":h")
end

return M
