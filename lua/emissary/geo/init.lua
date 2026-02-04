--- Point and Range geometry for buffer positions
-- @module emissary.geo
--
-- All positions are stored as 1-based row/col internally.
-- Conversion methods handle Vim and Treesitter coordinate systems.

local M = {}

---@class Point
---@field row number 1-based row
---@field col number 1-based column
local Point = {}
Point.__index = Point

--- Create a new Point
-- @param row number 1-based row
-- @param col number 1-based column
-- @return Point
function Point.new(row, col)
  local self = setmetatable({}, Point)
  self.row = row
  self.col = col
  return self
end

--- Create Point from Vim cursor position (1,1-based)
-- @param pos table {row, col} from getcurpos() or similar
-- @return Point
function Point.from_vim(pos)
  return Point.new(pos[1], pos[2])
end

--- Create Point from 0-based position (like Treesitter)
-- @param row number 0-based row
-- @param col number 0-based column
-- @return Point
function Point.from_ts(row, col)
  return Point.new(row + 1, col + 1)
end

--- Convert to Vim position (1,1-based)
-- @return number, number row, col
function Point:to_vim()
  return self.row, self.col
end

--- Convert to 0-based position (like Treesitter)
-- @return number, number row, col
function Point:to_ts()
  return self.row - 1, self.col - 1
end

--- Convert to API position (0-based row, 0-based col)
-- @return number, number row, col
function Point:to_api()
  return self.row - 1, self.col - 1
end

--- Check equality
-- @param other Point
-- @return boolean
function Point:equals(other)
  return self.row == other.row and self.col == other.col
end

--- Check if this point is before another
-- @param other Point
-- @return boolean
function Point:is_before(other)
  if self.row < other.row then
    return true
  elseif self.row == other.row then
    return self.col < other.col
  end
  return false
end

--- Clone this point
-- @return Point
function Point:clone()
  return Point.new(self.row, self.col)
end

function Point:__tostring()
  return string.format("Point(%d, %d)", self.row, self.col)
end

M.Point = Point

---@class Range
---@field start Point Start position (inclusive)
---@field finish Point End position (inclusive)
local Range = {}
Range.__index = Range

--- Create a new Range
-- @param start_point Point Start position
-- @param end_point Point End position
-- @return Range
function Range.new(start_point, end_point)
  local self = setmetatable({}, Range)
  -- Ensure start is before end
  if end_point:is_before(start_point) then
    self.start = end_point
    self.finish = start_point
  else
    self.start = start_point
    self.finish = end_point
  end
  return self
end

--- Create Range from visual selection
-- @return Range|nil Returns nil if no valid selection
function Range.from_visual_selection()
  -- Get visual selection marks
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  -- Validate positions
  if start_pos[2] == 0 or end_pos[2] == 0 then
    return nil
  end

  local start_point = Point.new(start_pos[2], start_pos[3])
  local end_point = Point.new(end_pos[2], end_pos[3])

  return Range.new(start_point, end_point)
end

--- Create Range from current visual selection (while still in visual mode)
-- @return Range|nil
function Range.from_current_visual()
  -- Get cursor and visual start positions
  local cursor = vim.fn.getpos(".")
  local visual_start = vim.fn.getpos("v")

  if cursor[2] == 0 or visual_start[2] == 0 then
    return nil
  end

  local cursor_point = Point.new(cursor[2], cursor[3])
  local start_point = Point.new(visual_start[2], visual_start[3])

  return Range.new(start_point, cursor_point)
end

--- Create Range from two 0-based positions
-- @param start_row number
-- @param start_col number
-- @param end_row number
-- @param end_col number
-- @return Range
function Range.from_ts(start_row, start_col, end_row, end_col)
  return Range.new(
    Point.from_ts(start_row, start_col),
    Point.from_ts(end_row, end_col)
  )
end

--- Convert to Vim positions
-- @return number, number, number, number start_row, start_col, end_row, end_col
function Range:to_vim()
  local sr, sc = self.start:to_vim()
  local er, ec = self.finish:to_vim()
  return sr, sc, er, ec
end

--- Convert to API positions (0-based)
-- @return number, number, number, number
function Range:to_api()
  local sr, sc = self.start:to_api()
  local er, ec = self.finish:to_api()
  return sr, sc, er, ec
end

--- Get the text within this range from a buffer
-- @param bufnr number Buffer number
-- @return string
function Range:get_text(bufnr)
  local start_row, start_col, end_row, end_col = self:to_api()

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
  if #lines == 0 then
    return ""
  end

  -- Handle single line
  -- end_col is 0-based from to_api(), but our range is inclusive
  -- Lua string.sub is 1-based and inclusive, so we need end_col + 1
  if #lines == 1 then
    return string.sub(lines[1], start_col + 1, end_col + 1)
  end

  -- Handle multi-line
  lines[1] = string.sub(lines[1], start_col + 1)
  lines[#lines] = string.sub(lines[#lines], 1, end_col + 1)

  return table.concat(lines, "\n")
end

--- Set text within this range in a buffer
-- @param bufnr number Buffer number
-- @param text string|table New text (string or lines)
function Range:set_text(bufnr, text)
  local start_row, start_col, end_row, end_col = self:to_api()

  local lines
  if type(text) == "string" then
    lines = vim.split(text, "\n", { plain = true })
  else
    lines = text
  end

  -- nvim_buf_set_text uses exclusive end_col, but our range is inclusive
  -- So we need to add 1 to end_col to include the last character
  -- BUT we must clamp to actual line length for empty lines
  local end_line = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1] or ""
  local actual_end_col = math.min(end_col + 1, #end_line)

  vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, actual_end_col, lines)
end

--- Check if a point is within this range
-- @param point Point
-- @return boolean
function Range:contains(point)
  if point.row < self.start.row or point.row > self.finish.row then
    return false
  end
  if point.row == self.start.row and point.col < self.start.col then
    return false
  end
  if point.row == self.finish.row and point.col > self.finish.col then
    return false
  end
  return true
end

--- Get line count of this range
-- @return number
function Range:line_count()
  return self.finish.row - self.start.row + 1
end

--- Clone this range
-- @return Range
function Range:clone()
  return Range.new(self.start:clone(), self.finish:clone())
end

function Range:__tostring()
  return string.format("Range(%s -> %s)", tostring(self.start), tostring(self.finish))
end

M.Range = Range

return M
