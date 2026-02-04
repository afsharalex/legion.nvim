--- Extmark utilities for range tracking
-- @module emissary.ops.marks
--
-- Uses Neovim extmarks with proper gravity settings to track
-- text ranges even as the buffer is edited.

local state = require("emissary.state")
local geo = require("emissary.geo")

local M = {}

---@class MarkPair
---@field start_id number Start extmark ID
---@field end_id number End extmark ID
---@field bufnr number Buffer number

--- Clamp column to valid range for a line
-- @param bufnr number Buffer number
-- @param row number 0-based row
-- @param col number 0-based column
-- @return number Clamped column
local function clamp_col(bufnr, row, col)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if not line then
    return 0
  end
  local max_col = #line
  return math.min(col, max_col)
end

--- Create extmarks to track a range
-- @param bufnr number Buffer number
-- @param range Range The range to track
-- @return MarkPair|nil Mark pair or nil on error
function M.mark_range(bufnr, range)
  local nsid = state.init()

  local start_row, start_col, end_row, end_col = range:to_api()

  -- Clamp columns to valid line lengths (visual mode can return values beyond line end)
  start_col = clamp_col(bufnr, start_row, start_col)
  end_col = clamp_col(bufnr, end_row, end_col)

  -- Start mark: right_gravity = false means it stays at insertion point
  -- Text inserted at this position appears AFTER the mark
  local start_id = vim.api.nvim_buf_set_extmark(bufnr, nsid, start_row, start_col, {
    right_gravity = false,
  })

  -- End mark: right_gravity = true means text inserted appears BEFORE the mark
  -- This keeps the end mark at the end of the selection
  local end_id = vim.api.nvim_buf_set_extmark(bufnr, nsid, end_row, end_col, {
    right_gravity = true,
  })

  return {
    start_id = start_id,
    end_id = end_id,
    bufnr = bufnr,
  }
end

--- Get current range from marks
-- @param marks MarkPair The mark pair
-- @return Range|nil Current range or nil if marks invalid
function M.get_range_from_marks(marks)
  if not marks or not M.is_valid(marks) then
    return nil
  end

  local nsid = state.init()

  local start_mark = vim.api.nvim_buf_get_extmark_by_id(
    marks.bufnr, nsid, marks.start_id, {}
  )
  local end_mark = vim.api.nvim_buf_get_extmark_by_id(
    marks.bufnr, nsid, marks.end_id, {}
  )

  if #start_mark == 0 or #end_mark == 0 then
    return nil
  end

  -- Extmarks return 0-based positions
  return geo.Range.from_ts(
    start_mark[1], start_mark[2],
    end_mark[1], end_mark[2]
  )
end

--- Check if marks are still valid
-- @param marks MarkPair
-- @return boolean
function M.is_valid(marks)
  if not marks then
    return false
  end

  -- Check if buffer is valid
  if not vim.api.nvim_buf_is_valid(marks.bufnr) then
    return false
  end

  local nsid = state.init()

  -- Check if extmarks exist
  local start_mark = vim.api.nvim_buf_get_extmark_by_id(
    marks.bufnr, nsid, marks.start_id, {}
  )
  local end_mark = vim.api.nvim_buf_get_extmark_by_id(
    marks.bufnr, nsid, marks.end_id, {}
  )

  return #start_mark > 0 and #end_mark > 0
end

--- Delete marks
-- @param marks MarkPair
function M.delete_marks(marks)
  if not marks then
    return
  end

  if not vim.api.nvim_buf_is_valid(marks.bufnr) then
    return
  end

  local nsid = state.init()

  pcall(vim.api.nvim_buf_del_extmark, marks.bufnr, nsid, marks.start_id)
  pcall(vim.api.nvim_buf_del_extmark, marks.bufnr, nsid, marks.end_id)
end

--- Get text from marked range
-- @param marks MarkPair
-- @return string|nil Text or nil if marks invalid
function M.get_text(marks)
  local range = M.get_range_from_marks(marks)
  if not range then
    return nil
  end
  return range:get_text(marks.bufnr)
end

--- Replace text in marked range
-- @param marks MarkPair
-- @param text string New text
-- @return boolean Success
function M.replace_text(marks, text)
  local range = M.get_range_from_marks(marks)
  if not range then
    return false
  end

  range:set_text(marks.bufnr, text)
  return true
end

return M
