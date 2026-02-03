--- Operation class - represents one highlighted block being processed
-- @module pear.core.operation

local id_gen = require("pear.core.id")
local state = require("pear.state")

local M = {}
M.__index = M

--- Operation status values
M.STATUS = {
  PENDING = "pending",
  RUNNING = "running",
  COMPLETED = "completed",
  FAILED = "failed",
  CANCELLED = "cancelled",
}

--- Create a new Operation
-- @param opts table Options
-- @param opts.bufnr number Buffer number
-- @param opts.range Range The range being processed
-- @param opts.instruction string The user instruction
-- @return Operation
function M.new(opts)
  local self = setmetatable({}, M)

  self.id = id_gen.generate()
  self.short_id = id_gen.short()
  self.bufnr = opts.bufnr
  self.range = opts.range
  self.instruction = opts.instruction or ""
  self.status = M.STATUS.PENDING

  -- Will be set during execution
  self.marks = nil
  self.client = nil
  self.status_display = nil
  self.spinner_timer = nil
  self.status_extmark_id = nil
  self.accumulated_text = ""
  self.error = nil
  self.cleaned_up = false

  -- Register with state
  state.register(self)

  return self
end

--- Check if operation is still active
-- @return boolean
function M:is_active()
  return self.status == M.STATUS.PENDING or self.status == M.STATUS.RUNNING
end

--- Check if operation completed successfully
-- @return boolean
function M:is_success()
  return self.status == M.STATUS.COMPLETED
end

--- Mark operation as running
function M:start()
  self.status = M.STATUS.RUNNING
end

--- Mark operation as completed
function M:complete()
  self.status = M.STATUS.COMPLETED
end

--- Mark operation as failed
-- @param err string|nil Error message
function M:fail(err)
  self.status = M.STATUS.FAILED
  self.error = err
end

--- Cancel the operation
function M:cancel()
  if not self:is_active() then
    return
  end

  self.status = M.STATUS.CANCELLED

  -- Disconnect client if running
  if self.client then
    pcall(function()
      self.client:disconnect()
    end)
  end
end

--- Get a summary of this operation for display
-- @return string
function M:summary()
  local instr = self.instruction or ""
  if #instr > 30 then
    instr = string.sub(instr, 1, 27) .. "..."
  end
  return string.format("[%s] %s: %s", self.short_id, self.status, instr)
end

return M
