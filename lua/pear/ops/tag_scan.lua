--- Docstring tag scanning operation
-- @module pear.ops.tag_scan
--
-- Scan for @llm tags in docstrings and implement tagged elements

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

--- Find the end of a code block (function, class, etc.) starting from a given line
-- Uses indentation-based heuristics and common patterns
-- @param bufnr number Buffer number
-- @param start_row number 1-based starting row
-- @return number End row (1-based)
local function find_block_end(bufnr, start_row)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row - 1, line_count, false)

  if #lines == 0 then
    return start_row
  end

  -- Get the indentation of the first line (the function/class definition)
  local first_line = lines[1]
  local base_indent = first_line:match("^(%s*)")
  local base_indent_len = #base_indent

  -- Check for single-line constructs
  local filetype = vim.bo[bufnr].filetype

  -- For brace-based languages, track brace depth
  if filetype == "lua" or filetype == "python" or filetype == "javascript" or
     filetype == "typescript" or filetype == "go" or filetype == "rust" or
     filetype == "c" or filetype == "cpp" or filetype == "java" then

    -- Python uses indentation
    if filetype == "python" then
      for i = 2, #lines do
        local line = lines[i]
        -- Skip empty lines and comments
        if line:match("^%s*$") or line:match("^%s*#") then
          -- Continue
        else
          local indent = line:match("^(%s*)")
          if #indent <= base_indent_len then
            -- Found a line at same or lower indentation
            return start_row + i - 2
          end
        end
      end
      return start_row + #lines - 1
    end

    -- Lua uses 'end' keyword
    if filetype == "lua" then
      local depth = 0
      for i = 1, #lines do
        local line = lines[i]
        -- Count function/if/for/while openings
        depth = depth + select(2, line:gsub("%f[%w]function%f[%W]", ""))
        depth = depth + select(2, line:gsub("%f[%w]if%f[%W]", ""))
        depth = depth + select(2, line:gsub("%f[%w]for%f[%W]", ""))
        depth = depth + select(2, line:gsub("%f[%w]while%f[%W]", ""))
        depth = depth + select(2, line:gsub("%f[%w]do%f[%W]", ""))
        -- Count 'end' closings
        depth = depth - select(2, line:gsub("%f[%w]end%f[%W]", ""))

        if i > 1 and depth <= 0 then
          return start_row + i - 1
        end
      end
      return start_row + #lines - 1
    end

    -- Brace-based languages
    local depth = 0
    local found_brace = false
    for i = 1, #lines do
      local line = lines[i]
      for j = 1, #line do
        local char = line:sub(j, j)
        if char == "{" then
          depth = depth + 1
          found_brace = true
        elseif char == "}" then
          depth = depth - 1
          if found_brace and depth == 0 then
            return start_row + i - 1
          end
        end
      end
    end
  end

  -- Fallback: use indentation
  for i = 2, #lines do
    local line = lines[i]
    if not line:match("^%s*$") then
      local indent = line:match("^(%s*)")
      if #indent <= base_indent_len then
        return start_row + i - 2
      end
    end
  end

  return start_row + #lines - 1
end

--- Scan buffer for @llm tags
-- @param bufnr number Buffer number
-- @return table List of {range, instruction, tag_line} for each found tag
function M.scan_buffer(bufnr)
  local results = {}
  local tag_pattern = config.get("tag_scan.pattern") or "@llm%s+(.+)"
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  for i, line in ipairs(lines) do
    local instruction = line:match(tag_pattern)
    if instruction then
      -- Found a tag, now find the element it applies to
      -- Look for the next non-comment, non-empty line
      local element_start = nil
      for j = i + 1, #lines do
        local next_line = lines[j]
        -- Skip empty lines and comment-only lines
        if not next_line:match("^%s*$") and
           not next_line:match("^%s*%-%-") and
           not next_line:match("^%s*#") and
           not next_line:match("^%s*//") and
           not next_line:match("^%s*/%*") and
           not next_line:match("^%s*%*") then
          element_start = j
          break
        end
      end

      if element_start then
        -- Find the end of the element (function, class, etc.)
        local element_end = find_block_end(bufnr, element_start)

        -- Find the start of the docstring block (including the @llm tag)
        local docstring_start = i
        for j = i - 1, 1, -1 do
          local prev_line = lines[j]
          -- Continue if it's a comment line
          if prev_line:match("^%s*%-%-") or
             prev_line:match("^%s*#") or
             prev_line:match("^%s*//") or
             prev_line:match("^%s*/%*") or
             prev_line:match("^%s*%*") or
             prev_line:match("^%s*'''") or
             prev_line:match("^%s*\"\"\"") then
            docstring_start = j
          else
            break
          end
        end

        -- Get the line lengths for proper range
        local start_line = lines[docstring_start]
        local end_line = lines[element_end]

        local range = geo.Range.new(
          geo.Point.new(docstring_start, 1),
          geo.Point.new(element_end, #end_line)
        )

        table.insert(results, {
          range = range,
          instruction = vim.trim(instruction),
          tag_line = i,
        })
      end
    end
  end

  return results
end

--- Execute a single tag implementation
-- @param opts table Options
-- @param opts.bufnr number Buffer number
-- @param opts.range Range The range to replace
-- @param opts.instruction string The instruction from the tag
-- @return Operation The created operation
function M.execute_single(opts)
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
  log.info("Starting tag implementation operation")
  log.debug("Tag instruction: " .. instruction)

  -- Create extmarks to track the range
  op.marks = marks.mark_range(bufnr, range)
  if not op.marks then
    log.error("Failed to create tracking marks")
    op:fail("Failed to create tracking marks")
    log.clear_operation()
    return op
  end

  -- Get the element text
  local element_text = range:get_text(bufnr)
  if not element_text or #element_text == 0 then
    log.warn("No element text found")
    op:fail("No element text found")
    cleanup.cleanup_operation(op)
    log.clear_operation()
    return op
  end

  log.debug("Element text: " .. #element_text .. " chars")

  -- Get file context
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.bo[bufnr].filetype

  -- Build prompt options
  local prompt_opts = {
    element_text = element_text,
    tag_instruction = instruction,
    filename = filename,
    filetype = filetype,
  }

  -- Include full file contents if enabled
  if config.get("full_file_context") ~= false then
    local file_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    prompt_opts.file_contents = table.concat(file_lines, "\n")
  end

  -- Build the prompt
  local prompt = builder.build_tag_prompt(prompt_opts)

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

      local preview = accumulated
      if #preview > 50 then
        preview = string.sub(preview, 1, 47) .. "..."
      end
      op.status_display.set_preview(preview)
    end,
    on_done = function(result)
      if not op:is_active() then
        do_cleanup()
        log.clear_operation()
        return
      end

      local implementation = op.accumulated_text
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

  text = vim.trim(text)

  local fenced = text:match("^```[^\n]*\n(.-)```$")
  if fenced then
    text = fenced
  end

  return text
end

--- Execute all @llm tags in a buffer
-- @param bufnr number Buffer number
function M.execute_all(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Scan for tags
  local tags = M.scan_buffer(bufnr)

  if #tags == 0 then
    window.notify("Pear: No @llm tags found in buffer", vim.log.levels.INFO)
    return
  end

  window.notify(string.format("Pear: Found %d @llm tag(s), implementing...", #tags), vim.log.levels.INFO)

  -- Process tags from bottom to top to avoid range invalidation
  -- (replacing earlier text would shift line numbers for later tags)
  table.sort(tags, function(a, b)
    return a.range.start.row > b.range.start.row
  end)

  -- Execute each tag implementation sequentially
  local function process_next(index)
    if index > #tags then
      return
    end

    local tag = tags[index]
    local op = M.execute_single({
      bufnr = bufnr,
      range = tag.range,
      instruction = tag.instruction,
    })

    -- Wait for completion before processing next
    -- We use a simple polling approach since operations are async
    local check_timer = vim.loop.new_timer()
    check_timer:start(100, 100, vim.schedule_wrap(function()
      if not op:is_active() then
        check_timer:stop()
        check_timer:close()
        process_next(index + 1)
      end
    end))
  end

  process_next(1)
end

return M
