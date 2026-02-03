--- Status display with spinner animation
-- @module pear.ui.status

local state = require("pear.state")
local config = require("pear.config")

local M = {}

--- Braille spinner characters
local SPINNER_FRAMES = {
  "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"
}

--- Create a status display for an operation
-- @param operation table The operation object
-- @return table Status controller
function M.create(operation)
  local self = {
    operation = operation,
    frame = 1,
    timer = nil,
    extmark_id = nil,
    message = "Working...",
    preview = "",
  }

  --- Update the virtual text display
  local function update_display()
    if not vim.api.nvim_buf_is_valid(operation.bufnr) then
      return
    end

    local nsid = state.init()

    -- Get current position (line above the marked range)
    local marks = require("pear.ops.marks")
    local range = marks.get_range_from_marks(operation.marks)
    if not range then
      return
    end

    local line = range.start.row - 1  -- 0-based, line above
    if line < 0 then
      line = 0
    end

    -- Build status text
    local spinner = SPINNER_FRAMES[self.frame]
    local status_text = string.format(" %s %s", spinner, self.message)

    -- Add preview if available and enabled
    local preview_text = ""
    if config.get("ui.show_preview") and self.preview and #self.preview > 0 then
      local max_lines = config.get("ui.preview_max_lines") or 3
      local lines = vim.split(self.preview, "\n")
      if #lines > max_lines then
        lines = vim.list_slice(lines, 1, max_lines)
        table.insert(lines, "...")
      end
      preview_text = " │ " .. table.concat(lines, " ")
      -- Truncate if too long
      if #preview_text > 60 then
        preview_text = string.sub(preview_text, 1, 57) .. "..."
      end
    end

    -- Create or update extmark with virtual text
    local opts = {
      id = self.extmark_id,
      virt_text = {
        { status_text, "PearStatus" },
        { preview_text, "PearPreview" },
      },
      virt_text_pos = "eol",
    }

    self.extmark_id = vim.api.nvim_buf_set_extmark(operation.bufnr, nsid, line, 0, opts)
    operation.status_extmark_id = self.extmark_id
  end

  --- Start the spinner animation
  function self.start()
    if self.timer then
      return
    end

    local interval = config.get("ui.spinner_interval") or 80

    self.timer = vim.uv.new_timer()
    self.timer:start(0, interval, vim.schedule_wrap(function()
      self.frame = (self.frame % #SPINNER_FRAMES) + 1
      update_display()
    end))

    operation.spinner_timer = self.timer
  end

  --- Stop the spinner animation
  function self.stop()
    if self.timer then
      self.timer:stop()
      self.timer:close()
      self.timer = nil
      operation.spinner_timer = nil
    end
  end

  --- Update the status message
  -- @param msg string New message
  function self.set_message(msg)
    self.message = msg
    update_display()
  end

  --- Update the preview text
  -- @param text string Preview text
  function self.set_preview(text)
    self.preview = text
  end

  --- Show completion status
  -- @param success boolean Whether operation succeeded
  function self.complete(success)
    self.stop()

    if not vim.api.nvim_buf_is_valid(operation.bufnr) then
      return
    end

    local nsid = state.init()

    -- Get position
    local marks = require("pear.ops.marks")
    local range = marks.get_range_from_marks(operation.marks)
    if not range then
      return
    end

    local line = range.start.row - 1
    if line < 0 then
      line = 0
    end

    -- Show brief completion message
    local icon = success and "✓" or "✗"
    local msg = success and "Done" or "Failed"
    local hl = success and "PearStatusComplete" or "PearStatusError"

    local opts = {
      id = self.extmark_id,
      virt_text = {{ string.format(" %s %s", icon, msg), hl }},
      virt_text_pos = "eol",
    }

    self.extmark_id = vim.api.nvim_buf_set_extmark(operation.bufnr, nsid, line, 0, opts)

    -- Clear after a short delay
    vim.defer_fn(function()
      if self.extmark_id and vim.api.nvim_buf_is_valid(operation.bufnr) then
        pcall(vim.api.nvim_buf_del_extmark, operation.bufnr, nsid, self.extmark_id)
        self.extmark_id = nil
        operation.status_extmark_id = nil
      end
    end, 2000)
  end

  --- Clear the status display
  function self.clear()
    self.stop()
    if self.extmark_id and vim.api.nvim_buf_is_valid(operation.bufnr) then
      local nsid = state.init()
      pcall(vim.api.nvim_buf_del_extmark, operation.bufnr, nsid, self.extmark_id)
      self.extmark_id = nil
      operation.status_extmark_id = nil
    end
  end

  return self
end

return M
