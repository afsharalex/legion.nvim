--- Build prompts with context
-- @module emissary.prompt.builder

local M = {}

--- Build a prompt for visual selection replacement
-- @param opts table Options
-- @param opts.instruction string User instruction
-- @param opts.selected_text string The selected text
-- @param opts.filename string|nil Current filename
-- @param opts.filetype string|nil Current filetype
-- @param opts.file_contents string|nil Full file contents
-- @param opts.selection_range table|nil Selection range {start_row, end_row}
-- @return string The built prompt
function M.build_replace_prompt(opts)
  local parts = {}

  -- Add context about what we're doing
  table.insert(parts, "You are helping edit code in a file.")
  table.insert(parts, "I've selected a block of code and want you to modify it according to my instruction.")
  table.insert(parts, "")

  -- Selection location
  table.insert(parts, "<SELECTION_LOCATION>")
  if opts.filename then
    table.insert(parts, string.format("File: %s", opts.filename))
  end
  if opts.filetype and opts.filetype ~= "" then
    table.insert(parts, string.format("Language: %s", opts.filetype))
  end
  if opts.selection_range then
    table.insert(parts, string.format("Lines: %d-%d", opts.selection_range.start_row, opts.selection_range.end_row))
  end
  table.insert(parts, "</SELECTION_LOCATION>")
  table.insert(parts, "")

  -- Selection content
  table.insert(parts, "<SELECTION_CONTENT>")
  table.insert(parts, opts.selected_text)
  table.insert(parts, "</SELECTION_CONTENT>")
  table.insert(parts, "")

  -- Full file contents
  if opts.file_contents then
    table.insert(parts, "<FILE_CONTAINING_SELECTION>")
    table.insert(parts, opts.file_contents)
    table.insert(parts, "</FILE_CONTAINING_SELECTION>")
    table.insert(parts, "")
  end

  -- Instruction
  table.insert(parts, "<INSTRUCTION>")
  table.insert(parts, opts.instruction)
  table.insert(parts, "</INSTRUCTION>")
  table.insert(parts, "")

  -- Output format
  table.insert(parts, "IMPORTANT: Respond with ONLY the replacement code.")
  table.insert(parts, "Do not include any explanation, markdown code fences, or surrounding text.")
  table.insert(parts, "Your entire response will directly replace the selected code.")

  return table.concat(parts, "\n")
end

--- Get full file contents
-- @param bufnr number Buffer number
-- @return string
function M.get_file_contents(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

--- Get context lines around a range (kept for backward compatibility)
-- @param bufnr number Buffer number
-- @param range Range The selection range
-- @param context_lines number Number of context lines (default 5)
-- @return string, string context_before, context_after
function M.get_context(bufnr, range, context_lines)
  context_lines = context_lines or 5

  local start_row = range.start.row
  local end_row = range.finish.row

  -- Get lines before
  local before_start = math.max(1, start_row - context_lines)
  local before_end = start_row - 1
  local context_before = ""
  if before_end >= before_start then
    local lines = vim.api.nvim_buf_get_lines(bufnr, before_start - 1, before_end, false)
    context_before = table.concat(lines, "\n")
  end

  -- Get lines after
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  local after_start = end_row + 1
  local after_end = math.min(total_lines, end_row + context_lines)
  local context_after = ""
  if after_end >= after_start then
    local lines = vim.api.nvim_buf_get_lines(bufnr, after_start - 1, after_end, false)
    context_after = table.concat(lines, "\n")
  end

  return context_before, context_after
end

--- Build a simple instruction prompt (no file context)
-- @param instruction string The instruction
-- @param text string The text to process
-- @return string
function M.build_simple_prompt(instruction, text)
  return string.format([[%s

Here is the text:
```
%s
```

Respond with ONLY the modified text, no explanations or code fences.]], instruction, text)
end

--- Build a prompt for line replacement/insertion (normal mode)
-- @param opts table Options
-- @param opts.instruction string User instruction
-- @param opts.line_text string The selected line(s) text (may be empty)
-- @param opts.is_empty_line boolean Whether the cursor is on an empty line
-- @param opts.filename string|nil Current filename
-- @param opts.filetype string|nil Current filetype
-- @param opts.file_contents string|nil Full file contents
-- @param opts.line_range table|nil Line range {start_row, end_row}
-- @return string The built prompt
function M.build_line_prompt(opts)
  local parts = {}

  local is_empty = opts.is_empty_line

  if is_empty then
    table.insert(parts, "You are helping write code at a specific location in a file.")
    table.insert(parts, "The cursor is on an empty line. Generate code according to the instruction.")
  else
    table.insert(parts, "You are helping edit code at a specific location in a file.")
    table.insert(parts, "Modify or replace the current line(s) according to the instruction.")
  end
  table.insert(parts, "")

  -- Cursor location
  table.insert(parts, "<CURSOR_LOCATION>")
  if opts.filename then
    table.insert(parts, string.format("File: %s", opts.filename))
  end
  if opts.filetype and opts.filetype ~= "" then
    table.insert(parts, string.format("Language: %s", opts.filetype))
  end
  if opts.line_range then
    if opts.line_range.start_row == opts.line_range.end_row then
      table.insert(parts, string.format("Line: %d", opts.line_range.start_row))
    else
      table.insert(parts, string.format("Lines: %d-%d", opts.line_range.start_row, opts.line_range.end_row))
    end
  end
  table.insert(parts, "</CURSOR_LOCATION>")
  table.insert(parts, "")

  -- Current line content (if not empty)
  if not is_empty then
    table.insert(parts, "<CURRENT_LINE>")
    table.insert(parts, opts.line_text)
    table.insert(parts, "</CURRENT_LINE>")
    table.insert(parts, "")
  end

  -- Full file contents for context
  if opts.file_contents then
    table.insert(parts, "<FILE_CONTEXT>")
    table.insert(parts, opts.file_contents)
    table.insert(parts, "</FILE_CONTEXT>")
    table.insert(parts, "")
  end

  -- Instruction
  table.insert(parts, "<INSTRUCTION>")
  table.insert(parts, opts.instruction)
  table.insert(parts, "</INSTRUCTION>")
  table.insert(parts, "")

  -- Output format
  table.insert(parts, "CRITICAL OUTPUT RULES:")
  if is_empty then
    table.insert(parts, "1. Return ONLY the new code to insert at the cursor position")
  else
    table.insert(parts, "1. Return ONLY the replacement for the current line(s)")
  end
  table.insert(parts, "2. Do NOT return the entire file - just the code for this location")
  table.insert(parts, "3. No explanations, no markdown fences - just the code")
  table.insert(parts, "4. Match the indentation style of the surrounding code")

  return table.concat(parts, "\n")
end

--- Build a prompt for function implementation
-- @param opts table Options
-- @param opts.function_stub string The function stub/signature
-- @param opts.filename string|nil Current filename
-- @param opts.filetype string|nil Current filetype
-- @param opts.file_contents string|nil Full file contents for context
-- @return string The built prompt
function M.build_implement_prompt(opts)
  local parts = {}

  table.insert(parts, "You are helping implement a function in a codebase.")
  table.insert(parts, "I've selected a function stub/signature and want you to implement the function body.")
  table.insert(parts, "")

  -- Context
  table.insert(parts, "<FUNCTION_STUB>")
  table.insert(parts, opts.function_stub)
  table.insert(parts, "</FUNCTION_STUB>")
  table.insert(parts, "")

  if opts.filename or opts.filetype then
    table.insert(parts, "<FILE_INFO>")
    if opts.filename then
      table.insert(parts, string.format("File: %s", opts.filename))
    end
    if opts.filetype and opts.filetype ~= "" then
      table.insert(parts, string.format("Language: %s", opts.filetype))
    end
    table.insert(parts, "</FILE_INFO>")
    table.insert(parts, "")
  end

  if opts.file_contents then
    table.insert(parts, "<FILE_CONTEXT>")
    table.insert(parts, opts.file_contents)
    table.insert(parts, "</FILE_CONTEXT>")
    table.insert(parts, "")
  end

  -- Output format
  table.insert(parts, "IMPORTANT: Implement this function.")
  table.insert(parts, "Return ONLY the complete function with its implementation.")
  table.insert(parts, "Do not include any explanation, markdown code fences, or surrounding text.")
  table.insert(parts, "Your entire response will directly replace the function stub.")

  return table.concat(parts, "\n")
end

--- Build a prompt for implementing a tagged element
-- @param opts table Options
-- @param opts.element_text string The element to implement (function, class, etc.)
-- @param opts.tag_instruction string The instruction from the @llm tag
-- @param opts.filename string|nil Current filename
-- @param opts.filetype string|nil Current filetype
-- @param opts.file_contents string|nil Full file contents for context
-- @return string The built prompt
function M.build_tag_prompt(opts)
  local parts = {}

  table.insert(parts, "You are helping modify code based on an @llm tag instruction.")
  table.insert(parts, "")

  -- Element context
  table.insert(parts, "<CODE_WITH_TAG>")
  table.insert(parts, opts.element_text)
  table.insert(parts, "</CODE_WITH_TAG>")
  table.insert(parts, "")

  -- Tag instruction
  table.insert(parts, "<INSTRUCTION>")
  table.insert(parts, opts.tag_instruction)
  table.insert(parts, "</INSTRUCTION>")
  table.insert(parts, "")

  -- File info (if available)
  if opts.filename or opts.filetype then
    table.insert(parts, "<FILE_INFO>")
    if opts.filename then
      table.insert(parts, string.format("File: %s", opts.filename))
    end
    if opts.filetype and opts.filetype ~= "" then
      table.insert(parts, string.format("Language: %s", opts.filetype))
    end
    table.insert(parts, "</FILE_INFO>")
    table.insert(parts, "")
  end

  if opts.file_contents then
    table.insert(parts, "<FILE_CONTEXT>")
    table.insert(parts, opts.file_contents)
    table.insert(parts, "</FILE_CONTEXT>")
    table.insert(parts, "")
  end

  -- Clear output instructions
  table.insert(parts, "CRITICAL OUTPUT RULES:")
  table.insert(parts, "1. Follow the instruction EXACTLY and MINIMALLY")
  table.insert(parts, "2. Remove the @llm tag line from your output")
  table.insert(parts, "3. Keep ALL existing code unchanged unless the instruction specifically asks to modify it")
  table.insert(parts, "4. If the instruction is to 'add a comment', return ONLY the comment line(s) plus the unchanged code")
  table.insert(parts, "5. Do not refactor, improve, or change anything beyond what the instruction asks")
  table.insert(parts, "6. No explanations, no markdown fences - just the code")
  table.insert(parts, "")
  table.insert(parts, "Your response replaces the CODE_WITH_TAG section. Return the minimal change needed.")

  return table.concat(parts, "\n")
end

return M
