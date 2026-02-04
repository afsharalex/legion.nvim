--- Global state management for concurrent operations
-- @module emissary.state

local M = {}

--- Active operations indexed by ID
M.operations = {}

--- Namespace ID for extmarks
M.nsid = nil

--- Initialize the state module
function M.init()
  if not M.nsid then
    M.nsid = vim.api.nvim_create_namespace("emissary")
  end
  return M.nsid
end

--- Register an operation
-- @param operation table The operation object
function M.register(operation)
  if operation and operation.id then
    M.operations[operation.id] = operation
  end
end

--- Unregister an operation
-- @param id string The operation ID
function M.unregister(id)
  if id then
    M.operations[id] = nil
  end
end

--- Get an operation by ID
-- @param id string The operation ID
-- @return table|nil The operation or nil
function M.get(id)
  return M.operations[id]
end

--- Get all active operations
-- @return table Array of operations
function M.get_all()
  local result = {}
  for _, op in pairs(M.operations) do
    table.insert(result, op)
  end
  return result
end

--- Get operations for a specific buffer
-- @param bufnr number Buffer number
-- @return table Array of operations
function M.get_for_buffer(bufnr)
  local result = {}
  for _, op in pairs(M.operations) do
    if op.bufnr == bufnr then
      table.insert(result, op)
    end
  end
  return result
end

--- Cancel all operations
function M.cancel_all()
  for id, op in pairs(M.operations) do
    if op.cancel then
      op:cancel()
    end
    M.operations[id] = nil
  end
end

--- Get count of active operations
-- @return number
function M.count()
  local n = 0
  for _ in pairs(M.operations) do
    n = n + 1
  end
  return n
end

--- Debug: print all operations
function M.debug_print()
  vim.print("Emissary operations:")
  for id, op in pairs(M.operations) do
    vim.print(string.format("  %s: buffer=%d, status=%s", id, op.bufnr or -1, op.status or "unknown"))
  end
end

return M
