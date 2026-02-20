--- Visual selection replace operation
-- @module legion.ops.visual_replace
--
-- Core operation: select text -> send to Claude -> replace with result

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

--- Safely convert error to string with detailed SDK error extraction
-- @param err any
-- @return string
local function safe_error_string(err)
  if err == nil then
    return "Unknown error"
  end

  -- Try to use SDK error type checking for better messages
  local sdk = provider.get_sdk()
  if sdk and type(err) == "table" then
    -- Check for specific SDK error types
    if sdk.is_error then
      if sdk.ProcessError and sdk.is_error(err, sdk.ProcessError) then
        local msg = err.message or "Process error"
        if err.exit_code then
          msg = msg .. " (exit code " .. tostring(err.exit_code) .. ")"
        end
        if err.stderr and #err.stderr > 0 then
          local stderr_preview = err.stderr:sub(1, 200)
          if #err.stderr > 200 then
            stderr_preview = stderr_preview .. "..."
          end
          msg = msg .. "\nstderr: " .. stderr_preview
        end
        return msg
      elseif sdk.CLINotFoundError and sdk.is_error(err, sdk.CLINotFoundError) then
        return "Claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code"
      elseif sdk.CLIConnectionError and sdk.is_error(err, sdk.CLIConnectionError) then
        return "CLI connection error: " .. (err.message or "unknown")
      end
    end
  end

  -- Handle our enhanced error objects (from on_exit handler)
  if type(err) == "table" then
    local parts = {}

    if err.message then
      table.insert(parts, tostring(err.message))
    elseif err.type == "exit" then
      local msg = "CLI exited"
      if err.code then
        msg = msg .. " with code " .. tostring(err.code)
      end
      if err.signal then
        msg = msg .. " (signal " .. tostring(err.signal) .. ")"
      end
      table.insert(parts, msg)
    end

    -- Add exit code if present and not already in message
    if err.exit_code and not err.message then
      table.insert(parts, "exit code " .. tostring(err.exit_code))
    end

    -- Add stderr preview if available
    if err.stderr and #err.stderr > 0 then
      local stderr_preview = err.stderr:sub(1, 200)
      if #err.stderr > 200 then
        stderr_preview = stderr_preview .. "..."
      end
      table.insert(parts, "stderr: " .. stderr_preview)
    end

    if #parts > 0 then
      return table.concat(parts, "\n")
    end

    -- Fallback for table errors
    if err.message then
      return tostring(err.message)
    end
    return "Error (table)"
  end

  -- Try tostring as last resort
  local ok, str = pcall(tostring, err)
  if ok then
    return str
  end

  return "Error (" .. type(err) .. ")"
end

--- Execute a visual replace operation
-- @param opts table Options
-- @param opts.bufnr number Buffer number
-- @param opts.range Range The visual selection range
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
  log.info("Starting visual replace operation")
  log.debug("Instruction: " .. instruction)

  -- Create extmarks to track the range
  op.marks = marks.mark_range(bufnr, range)
  if not op.marks then
    log.error("Failed to create tracking marks")
    op:fail("Failed to create tracking marks")
    log.clear_operation()
    return op
  end

  -- Get the selected text
  local selected_text = range:get_text(bufnr)
  if not selected_text or #selected_text == 0 then
    log.warn("No text selected")
    op:fail("No text selected")
    cleanup.cleanup_operation(op)
    log.clear_operation()
    return op
  end

  log.debug("Selected " .. #selected_text .. " chars of text")

  -- Get file context
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.bo[bufnr].filetype

  log.debug("File: " .. (filename ~= "" and filename or "(unnamed)") .. " [" .. (filetype or "no filetype") .. "]")

  -- Build prompt options
  local prompt_opts = {
    instruction = instruction,
    selected_text = selected_text,
    filename = filename,
    filetype = filetype,
    selection_range = {
      start_row = range.start.row,
      end_row = range.finish.row,
    },
  }

  -- Include full file contents if enabled (default: true)
  if config.get("full_file_context") ~= false then
    local file_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    prompt_opts.file_contents = table.concat(file_lines, "\n")
    log.debug("Including full file context: " .. #prompt_opts.file_contents .. " chars")
  else
    log.debug("Full file context disabled, sending selection only")
  end

  -- Build the prompt
  local prompt = builder.build_replace_prompt(prompt_opts)

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
      local replacement = op.accumulated_text

      -- Clean up the replacement text
      -- Remove markdown code fences if present
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
  -- Match ```language\n...\n``` or just ```\n...\n```
  local fenced = text:match("^```[^\n]*\n(.-)```$")
  if fenced then
    text = fenced
  end

  return text
end

--- Start a visual replace from current visual selection
-- @param instruction string|nil Optional instruction (prompts if nil)
function M.from_visual_selection(instruction)
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

  if instruction and #instruction > 0 then
    -- Execute immediately
    M.execute({
      bufnr = bufnr,
      range = range,
      instruction = instruction,
    })
  else
    -- Prompt for instruction
    window.capture_input({
      title = "Legion Instruction",
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

--- Start visual replace with prompt window
function M.with_prompt()
  M.from_visual_selection(nil)
end

return M
