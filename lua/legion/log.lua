--- Simple file logger for Legion
-- @module legion.log
--
-- Log to ~/.local/state/nvim/legion.log (XDG compliant)
-- Levels: DEBUG, INFO, WARN, ERROR
-- Format: [TIMESTAMP] [LEVEL] [OP:id] message

local M = {}

--- Log levels
M.levels = {
  DEBUG = 1,
  INFO = 2,
  WARN = 3,
  ERROR = 4,
}

--- Level names for output
local level_names = {
  [1] = "DEBUG",
  [2] = "INFO",
  [3] = "WARN",
  [4] = "ERROR",
}

--- Current configuration
local current_level = M.levels.INFO
local log_file_path = nil
local log_file_handle = nil
local operation_id = nil

--- Get the default log file path (XDG compliant)
-- @return string
local function get_default_log_path()
  local state_dir = vim.fn.stdpath("state")
  return state_dir .. "/legion.log"
end

--- Ensure log directory exists
-- @param path string Log file path
-- @return boolean
local function ensure_log_dir(path)
  local dir = vim.fn.fnamemodify(path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    local ok = vim.fn.mkdir(dir, "p")
    return ok == 1
  end
  return true
end

--- Open the log file
-- @return file|nil
local function open_log_file()
  if log_file_handle then
    return log_file_handle
  end

  local path = log_file_path or get_default_log_path()
  if not ensure_log_dir(path) then
    return nil
  end

  local handle, err = io.open(path, "a")
  if not handle then
    vim.notify("Legion: Failed to open log file: " .. (err or "unknown"), vim.log.levels.WARN)
    return nil
  end

  log_file_handle = handle
  return handle
end

--- Format a log message
-- @param level number Log level
-- @param msg string Message
-- @return string
local function format_message(level, msg)
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local level_str = level_names[level] or "UNKNOWN"
  local op_str = operation_id and string.format("[OP:%s] ", operation_id) or ""
  return string.format("[%s] [%-5s] %s%s\n", timestamp, level_str, op_str, msg)
end

--- Write a message to the log
-- @param level number Log level
-- @param msg string Message
local function write(level, msg)
  if level < current_level then
    return
  end

  local handle = open_log_file()
  if not handle then
    return
  end

  local formatted = format_message(level, msg)
  handle:write(formatted)
  handle:flush()
end

--- Initialize the logger
-- @param opts table|nil Options
-- @param opts.level string|nil Log level name (DEBUG, INFO, WARN, ERROR)
-- @param opts.file string|nil Custom log file path
function M.setup(opts)
  opts = opts or {}

  -- Set log level
  if opts.level then
    local level = M.levels[string.upper(opts.level)]
    if level then
      current_level = level
    end
  end

  -- Set custom file path
  if opts.file then
    log_file_path = opts.file
  end

  -- Close existing handle if changing path
  if log_file_handle then
    log_file_handle:close()
    log_file_handle = nil
  end
end

--- Set the current operation ID for context
-- @param id string|nil Operation ID
function M.set_operation(id)
  operation_id = id
end

--- Clear the current operation ID
function M.clear_operation()
  operation_id = nil
end

--- Log a debug message
-- @param msg string Message
function M.debug(msg)
  write(M.levels.DEBUG, msg)
end

--- Log an info message
-- @param msg string Message
function M.info(msg)
  write(M.levels.INFO, msg)
end

--- Log a warning message
-- @param msg string Message
function M.warn(msg)
  write(M.levels.WARN, msg)
end

--- Log an error message
-- @param msg string Message
function M.error(msg)
  write(M.levels.ERROR, msg)
end

--- Log with formatted string (like string.format)
-- @param level string Level name (debug, info, warn, error)
-- @param fmt string Format string
-- @param ... any Format arguments
function M.fmt(level, fmt, ...)
  local fn = M[string.lower(level)]
  if fn then
    local ok, msg = pcall(string.format, fmt, ...)
    if ok then
      fn(msg)
    else
      fn(fmt .. " (format error: " .. msg .. ")")
    end
  end
end

--- Get the current log file path
-- @return string
function M.get_log_path()
  return log_file_path or get_default_log_path()
end

--- Close the log file (for cleanup)
function M.close()
  if log_file_handle then
    log_file_handle:close()
    log_file_handle = nil
  end
end

return M
