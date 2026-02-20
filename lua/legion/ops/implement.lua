--- Function implementation operation
-- @module legion.ops.implement
--
-- Select a function stub/signature and Claude implements the body

local Operation = require("legion.core.operation")
local geo = require("legion.geo")
local marks = require("legion.ops.marks")
local cleanup = require("legion.ops.cleanup")
local provider = require("legion.sdk.provider")
local builder = require("legion.prompt.builder")
local status = require("legion.ui.status")
local window = require("legion.ui.window")
local log = require("legion.log")
local config = require("legion.config")
local git = require("legion.utils.git")

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

--- Execute a function implementation operation
-- @param opts table Options
-- @param opts.bufnr number Buffer number
-- @param opts.range Range The visual selection range
-- @return Operation The created operation
function M.execute(opts)
  local bufnr = opts.bufnr
  local range = opts.range

  -- Create operation
  local op = Operation.new({
    bufnr = bufnr,
    range = range,
    instruction = "Implement function",
  })

  -- Set operation context for logging
  log.set_operation(op.id)
  log.info("Starting function implementation operation")

  -- Create extmarks to track the range
  op.marks = marks.mark_range(bufnr, range)
  if not op.marks then
    log.error("Failed to create tracking marks")
    op:fail("Failed to create tracking marks")
    log.clear_operation()
    return op
  end

  -- Get the selected text (function stub)
  local function_stub = range:get_text(bufnr)
  if not function_stub or #function_stub == 0 then
    log.warn("No function stub selected")
    op:fail("No function stub selected")
    cleanup.cleanup_operation(op)
    log.clear_operation()
    return op
  end

  log.debug("Function stub: " .. #function_stub .. " chars")

  -- Get file context
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.bo[bufnr].filetype

  log.debug("File: " .. (filename ~= "" and filename or "(unnamed)") .. " [" .. (filetype or "no filetype") .. "]")

  -- Build prompt options
  local prompt_opts = {
    function_stub = function_stub,
    filename = filename,
    filetype = filetype,
  }

  -- Include full file contents if enabled (default: true)
  if config.get("full_file_context") ~= false then
    local file_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    prompt_opts.file_contents = table.concat(file_lines, "\n")
    log.debug("Including full file context: " .. #prompt_opts.file_contents .. " chars")
  end

  -- Build the prompt
  local prompt = builder.build_implement_prompt(prompt_opts)

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
      if not op:is_active() then
        return
      end

      local sdk = provider.get_sdk()
      if sdk and sdk.is_assistant_message(message) then
        -- Just keep showing "Implementing..."
      end
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
      local implementation = op.accumulated_text

      -- Clean up the response text
      implementation = M.clean_response(implementation)

      if #implementation == 0 then
        log.warn("Empty response received from Claude")
        op:fail("Empty response")
        op.status_display.complete(false)
        do_cleanup()
        log.clear_operation()
        return
      end

      log.info("Received " .. #implementation .. " chars, applying implementation")

      -- Apply the replacement
      local success = marks.replace_text(op.marks, implementation)

      if success then
        log.info("Operation completed successfully")
        op:complete()
        op.status_display.complete(true)
      else
        log.error("Failed to apply implementation")
        op:fail("Failed to apply implementation")
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

      window.notify("Legion error: " .. err_msg, vim.log.levels.ERROR)
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

--- Start function implementation from visual selection
function M.from_visual_selection()
  -- Get current buffer
  local bufnr = vim.api.nvim_get_current_buf()

  -- Exit visual mode to set '< and '> marks
  local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "x", false)

  -- Get the visual selection range
  local range = geo.Range.from_visual_selection()
  if not range then
    window.notify("No visual selection", vim.log.levels.WARN)
    return
  end

  -- Execute immediately
  M.execute({
    bufnr = bufnr,
    range = range,
  })
end

return M
