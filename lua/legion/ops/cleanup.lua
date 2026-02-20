--- Resource cleanup utilities
-- @module legion.ops.cleanup

local marks = require("legion.ops.marks")
local state = require("legion.state")
local config = require("legion.config")
local log = require("legion.log")

local M = {}

--- Clean up all resources for an operation
-- @param operation table The operation to clean up
function M.cleanup_operation(operation)
  if not operation then
    return
  end

  -- Stop timeout timer if running
  if operation.timeout_timer then
    pcall(function()
      operation.timeout_timer:stop()
      operation.timeout_timer:close()
    end)
    operation.timeout_timer = nil
  end

  -- Stop spinner timer if running
  if operation.spinner_timer then
    pcall(function()
      operation.spinner_timer:stop()
      operation.spinner_timer:close()
    end)
    operation.spinner_timer = nil
  end

  -- Clear status display (handles both start and end extmarks)
  if operation.status_display then
    pcall(function()
      operation.status_display.clear()
    end)
    operation.status_display = nil
  elseif operation.status_extmark_id and operation.bufnr then
    -- Fallback for legacy cleanup
    local nsid = state.init()
    if vim.api.nvim_buf_is_valid(operation.bufnr) then
      pcall(vim.api.nvim_buf_del_extmark, operation.bufnr, nsid, operation.status_extmark_id)
    end
    operation.status_extmark_id = nil
  end

  -- Delete tracking marks
  if operation.marks then
    marks.delete_marks(operation.marks)
    operation.marks = nil
  end

  -- Disconnect SDK client
  if operation.client then
    pcall(function()
      operation.client:disconnect()
    end)
    operation.client = nil
  end

  -- Unregister from state
  if operation.id then
    state.unregister(operation.id)
  end

  -- Mark as cleaned up
  operation.cleaned_up = true
end

--- Create a cleanup handler that ensures cleanup runs once
-- @param operation table The operation
-- @return function Cleanup function
function M.create_cleanup_handler(operation)
  local cleaned = false
  return function()
    if cleaned then
      return
    end
    cleaned = true
    M.cleanup_operation(operation)
  end
end

--- Clean up all operations (for plugin unload)
function M.cleanup_all()
  for _, op in pairs(state.operations) do
    M.cleanup_operation(op)
  end
  state.operations = {}
end

--- Start a timeout timer for an operation
-- @param operation table The operation
-- @param on_timeout function Callback when timeout occurs
-- @return boolean Whether timeout was started (false if timeout disabled)
function M.start_timeout(operation, on_timeout)
  local timeout_seconds = config.get("timeout") or 60
  if timeout_seconds <= 0 then
    return false
  end

  operation.timeout_timer = vim.loop.new_timer()
  operation.timeout_timer:start(timeout_seconds * 1000, 0, vim.schedule_wrap(function()
    if not operation:is_active() then
      return
    end

    log.warn("Operation timed out after " .. timeout_seconds .. " seconds")
    operation:fail("Timeout after " .. timeout_seconds .. "s")

    if on_timeout then
      on_timeout()
    end
  end))

  return true
end

return M
