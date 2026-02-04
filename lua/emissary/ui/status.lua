--- Status display with spinner animation
-- @module emissary.ui.status

local state = require("emissary.state")
local config = require("emissary.config")

local M = {}

--- Braille spinner characters
local SPINNER_FRAMES = {
  "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"
}

--- Create a status display for an operation
-- @param operation table The operation object
-- @return table Status controller
function M.create(operation)
  -- Determine if this is a multi-line selection at creation time
  -- (marks may shift during operation, so we capture this once)
  local marks = require("emissary.ops.marks")
  local initial_range = marks.get_range_from_marks(operation.marks)
  local is_multi_line = initial_range and (initial_range.finish.row ~= initial_range.start.row)

  -- Only show end indicator if:
  -- 1. It's a multi-line selection
  -- 2. The operation hasn't explicitly disabled it (e.g., tag_scan)
  local show_end_indicator = is_multi_line and (operation.show_end_indicator ~= false)

  local self = {
    operation = operation,
    frame = 1,
    timer = nil,
    extmark_id_start = nil,
    extmark_id_end = nil,
    show_end_indicator = show_end_indicator,
    message = "Working...",
    preview = "",
  }

  --- Update the virtual text display
  local function update_display()
    if not vim.api.nvim_buf_is_valid(operation.bufnr) then
      return
    end

    local nsid = state.init()

    -- Get current position from marks
    local range = marks.get_range_from_marks(operation.marks)
    if not range then
      return
    end

    local start_line = range.start.row - 1  -- 0-based
    if start_line < 0 then
      start_line = 0
    end

    local end_line = range.finish.row - 1  -- 0-based, at end of selection

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

    -- Start indicator (with message and preview)
    self.extmark_id_start = vim.api.nvim_buf_set_extmark(operation.bufnr, nsid, start_line, 0, {
      id = self.extmark_id_start,
      virt_text = {
        { status_text, "EmiStatus" },
        { preview_text, "EmiPreview" },
      },
      virt_text_pos = "eol",
    })
    operation.status_extmark_id = self.extmark_id_start

    -- End indicator (spinner only, shown for multi-line visual selections)
    -- Use show_end_indicator from creation time, not current position
    -- (marks shift during operation as text is added)
    if self.show_end_indicator then
      self.extmark_id_end = vim.api.nvim_buf_set_extmark(operation.bufnr, nsid, end_line, 0, {
        id = self.extmark_id_end,
        virt_text = {{ string.format(" %s", spinner), "EmiStatus" }},
        virt_text_pos = "eol",
      })
    end
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
    local range = marks.get_range_from_marks(operation.marks)
    if not range then
      return
    end

    local start_line = range.start.row - 1
    if start_line < 0 then
      start_line = 0
    end

    local end_line = range.finish.row - 1

    -- Show brief completion message
    local icon = success and "✓" or "✗"
    local msg = success and "Done" or "Failed"
    local hl = success and "EmiStatusComplete" or "EmiStatusError"

    -- Start indicator with full message
    self.extmark_id_start = vim.api.nvim_buf_set_extmark(operation.bufnr, nsid, start_line, 0, {
      id = self.extmark_id_start,
      virt_text = {{ string.format(" %s %s", icon, msg), hl }},
      virt_text_pos = "eol",
    })

    -- End indicator (icon only, for multi-line visual selections)
    -- Use show_end_indicator from creation time, not current position
    if self.show_end_indicator then
      self.extmark_id_end = vim.api.nvim_buf_set_extmark(operation.bufnr, nsid, end_line, 0, {
        id = self.extmark_id_end,
        virt_text = {{ string.format(" %s", icon), hl }},
        virt_text_pos = "eol",
      })
    end

    -- Clear after a short delay
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(operation.bufnr) then
        if self.extmark_id_start then
          pcall(vim.api.nvim_buf_del_extmark, operation.bufnr, nsid, self.extmark_id_start)
          self.extmark_id_start = nil
          operation.status_extmark_id = nil
        end
        if self.extmark_id_end then
          pcall(vim.api.nvim_buf_del_extmark, operation.bufnr, nsid, self.extmark_id_end)
          self.extmark_id_end = nil
        end
      end
    end, 2000)
  end

  --- Clear the status display
  function self.clear()
    self.stop()
    if vim.api.nvim_buf_is_valid(operation.bufnr) then
      local nsid = state.init()
      if self.extmark_id_start then
        pcall(vim.api.nvim_buf_del_extmark, operation.bufnr, nsid, self.extmark_id_start)
        self.extmark_id_start = nil
        operation.status_extmark_id = nil
      end
      if self.extmark_id_end then
        pcall(vim.api.nvim_buf_del_extmark, operation.bufnr, nsid, self.extmark_id_end)
        self.extmark_id_end = nil
      end
    end
  end

  return self
end

return M
