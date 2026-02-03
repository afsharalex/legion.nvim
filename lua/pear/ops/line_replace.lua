--- Normal mode line replace operation
-- @module pear.ops.line_replace
--
-- Operates on current line or a count of lines from cursor position

local Operation = require("pear.core.operation")
local geo = require("pear.geo")
local marks = require("pear.ops.marks")
local cleanup = require("pear.ops.cleanup")
local provider = require("pear.sdk.provider")
local builder = require("pear.prompt.builder")
local status = require("pear.ui.status")
local window = require("pear.ui.window")
local log = require("pear.log")
local config = require("pear.config")
local git = require("pear.utils.git")

local M = {}

--- Safely convert error to string
-- @param err any
-- @return string
local function safe_error_string(err)
  if err == nil then
    return "Unknown error"
  end

  if type(err) == "table" then
    if err.message then
      return tostring(err.message)
    end
    return "Error (table)"
  end

  local ok, str = pcall(tostring, err)
  if ok then
    return str
  end

  return "Error (" .. type(err) .. ")"
end

--- Execute a line replace operation
-- @param opts table Options
-- @param opts.bufnr number Buffer number
-- @param opts.range Range The line range
-- @param opts.instruction string The instruction for Claude
-- @return Operation The created operation
function M.execute(opts)
  local bufnr = opts.bufnr
  local range = opts.range
  local instruction = opts.instruction

  -- Create operation
  local op = Operation.new({
    bufnr = bufnr,
    range = range,
    instruction = instruction,
  })

  -- Set operation context for logging
  log.set_operation(op.id)
  log.info("Starting line replace operation")
  log.debug("Instruction: " .. instruction)

  -- Create extmarks to track the range
  op.marks = marks.mark_range(bufnr, range)
  if not op.marks then
    log.error("Failed to create tracking marks")
    op:fail("Failed to create tracking marks")
    log.clear_operation()
    return op
  end

  -- Get the current line text (may be empty - that's okay for insertions)
  local line_text = range:get_text(bufnr) or ""
  local is_empty_line = #line_text == 0 or line_text:match("^%s*$")

  log.debug("Line text: " .. (is_empty_line and "(empty)" or #line_text .. " chars"))

  -- Get file context
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.bo[bufnr].filetype

  log.debug("File: " .. (filename ~= "" and filename or "(unnamed)") .. " [" .. (filetype or "no filetype") .. "]")

  -- Build prompt options
  local prompt_opts = {
    instruction = instruction,
    line_text = line_text,
    is_empty_line = is_empty_line,
    filename = filename,
    filetype = filetype,
    line_range = {
      start_row = range.start.row,
      end_row = range.finish.row,
    },
  }

  -- Include full file contents if enabled (default: true)
  if config.get("full_file_context") ~= false then
    local file_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    prompt_opts.file_contents = table.concat(file_lines, "\n")
    log.debug("Including full file context: " .. #prompt_opts.file_contents .. " chars")
  end

  -- Build the prompt
  local prompt = builder.build_line_prompt(prompt_opts)

  -- Create status display
  op.status_display = status.create(op)
  op.status_display.set_message("Implementing...")
  op.status_display.start()

  -- Mark as running
  op:start()
  log.info("Operation started, connecting to Claude CLI")

  -- Create cleanup handler
  local do_cleanup = cleanup.create_cleanup_handler(op)

  -- Start timeout timer
  cleanup.start_timeout(op, function()
    op.status_display.complete(false)
    do_cleanup()
    log.clear_operation()
  end)

  -- Get cwd for SDK
  local cwd = git.get_cwd(filename)
  log.debug("Using cwd: " .. cwd)

  -- Start the SDK query
  op.client = provider.start_query({
    prompt = prompt,
    sdk_options = { cwd = cwd },
    on_message = function(message)
      -- Just keep showing "Implementing..."
    end,
    on_text = function(accumulated)
      if not op:is_active() then
        return
      end

      op.accumulated_text = accumulated

      -- Update preview with first bit of text
      local preview = accumulated
      if #preview > 50 then
        preview = string.sub(preview, 1, 47) .. "..."
      end
      op.status_display.set_preview(preview)
    end,
    on_done = function(result)
      if not op:is_active() then
        log.debug("on_done called but operation no longer active")
        do_cleanup()
        log.clear_operation()
        return
      end

      -- Get the final text
      local replacement = op.accumulated_text

      -- Clean up the replacement text
      replacement = M.clean_response(replacement)

      if #replacement == 0 then
        log.warn("Empty response received from Claude")
        op:fail("Empty response")
        op.status_display.complete(false)
        do_cleanup()
        log.clear_operation()
        return
      end

      log.info("Received " .. #replacement .. " chars, applying replacement")

      -- Apply the replacement
      local success = marks.replace_text(op.marks, replacement)

      if success then
        log.info("Operation completed successfully")
        op:complete()
        op.status_display.complete(true)
      else
        log.error("Failed to apply replacement text")
        op:fail("Failed to apply replacement")
        op.status_display.complete(false)
      end

      do_cleanup()
      log.clear_operation()
    end,
    on_error = function(err)
      if not op:is_active() then
        log.debug("on_error called but operation no longer active")
        do_cleanup()
        log.clear_operation()
        return
      end

      local err_msg = safe_error_string(err)
      log.error("Operation failed: " .. err_msg)
      op:fail(err_msg)
      op.status_display.complete(false)
      do_cleanup()
      log.clear_operation()

      window.notify("Pear error: " .. err_msg, vim.log.levels.ERROR)
    end,
  })

  if not op.client then
    log.error("Failed to create SDK client")
    op:fail("Failed to create SDK client")
    op.status_display.complete(false)
    do_cleanup()
    log.clear_operation()
  end

  return op
end

--- Clean response text (remove code fences, extra whitespace)
-- @param text string
-- @return string
function M.clean_response(text)
  if not text then
    return ""
  end

  -- Remove leading/trailing whitespace
  text = vim.trim(text)

  -- Remove markdown code fences if the entire response is wrapped in them
  local fenced = text:match("^```[^\n]*\n(.-)```$")
  if fenced then
    text = fenced
  end

  return text
end

--- Create a range for line(s) starting at a given row
-- @param bufnr number Buffer number
-- @param start_row number 1-based starting row
-- @param count number Number of lines
-- @return Range
local function create_line_range(bufnr, start_row, count)
  local end_row = start_row + count - 1

  -- Clamp to buffer bounds
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if end_row > line_count then
    end_row = line_count
  end

  -- Get line lengths for range
  local end_line = vim.api.nvim_buf_get_lines(bufnr, end_row - 1, end_row, false)[1] or ""

  -- Ensure end_col is at least 1 (for empty lines, col=0 is invalid in 1-based system)
  local end_col = math.max(1, #end_line)

  return geo.Range.new(
    geo.Point.new(start_row, 1),
    geo.Point.new(end_row, end_col)
  )
end

--- Start a line replace from a pre-captured position
-- Use this when buffer/cursor was captured before an async operation (like vim.ui.input)
-- @param bufnr number Buffer number
-- @param row number 1-based row number
-- @param count number Number of lines
-- @param instruction string The instruction
function M.from_position(bufnr, row, count, instruction)
  count = count or 1
  if count < 1 then
    count = 1
  end

  local range = create_line_range(bufnr, row, count)

  M.execute({
    bufnr = bufnr,
    range = range,
    instruction = instruction,
  })
end

--- Start a line replace from current line
-- @param instruction string|nil Optional instruction (prompts if nil or empty)
-- @param count number|nil Number of lines (default 1)
function M.from_current_line(instruction, count)
  local bufnr = vim.api.nvim_get_current_buf()
  count = count or 1
  if count < 1 then
    count = 1
  end

  -- Get cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local start_row = cursor[1]  -- 1-based row

  local range = create_line_range(bufnr, start_row, count)

  if instruction and #instruction > 0 then
    -- Execute immediately
    M.execute({
      bufnr = bufnr,
      range = range,
      instruction = instruction,
    })
  else
    -- Prompt for instruction
    -- Note: Capture bufnr and range before async input to avoid buffer switching issues
    window.capture_input({
      title = "Pear Line Instruction",
      callback = function(input)
        if input and #input > 0 then
          M.execute({
            bufnr = bufnr,
            range = range,
            instruction = input,
          })
        end
      end,
    })
  end
end

return M
