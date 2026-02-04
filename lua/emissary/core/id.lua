--- Unique ID generation for operations
-- @module emissary.core.id

local M = {}

--- Counter for unique IDs within session
local counter = 0

--- Generate a unique operation ID
-- @return string Unique ID in format "emi_XXXXXX_N"
function M.generate()
  counter = counter + 1
  -- Include timestamp for uniqueness across restarts
  local timestamp = os.time()
  return string.format("emi_%x_%d", timestamp, counter)
end

--- Generate a short ID (for display)
-- @return string Short ID in format "op_N"
function M.short()
  counter = counter + 1
  return string.format("op_%d", counter)
end

--- Reset counter (for testing)
function M.reset()
  counter = 0
end

return M
