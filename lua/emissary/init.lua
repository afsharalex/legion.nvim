--- Emissary: Neovim Plugin for Claude Code Integration
-- @module emissary
--
-- Allows developers to:
-- 1. Highlight text in Neovim
-- 2. Send instructions to Claude Code (runs in background, in parallel)
-- 3. Receive updates for that specific block
-- 4. Continue editing while Claude Code works

local M = {}

--- Plugin version
M.version = "0.1.0"

--- Setup the plugin with user configuration
-- @param user_config table|nil Configuration options
function M.setup(user_config)
  -- Load configuration
  local config = require("emissary.config")
  config.setup(user_config)

  -- Initialize logger
  local log = require("emissary.log")
  local log_config = config.get("log") or {}
  log.setup({
    level = log_config.level,
    file = log_config.file,
  })
  log.info("Emissary plugin initializing (v" .. M.version .. ")")

  -- Initialize state
  local state = require("emissary.state")
  state.init()

  -- Setup highlights
  local highlights = require("emissary.ui.highlights")
  highlights.setup()

  -- Create commands
  M._create_commands()

  -- Setup keymaps
  M._setup_keymaps()

  -- Verify SDK is available
  local provider = require("emissary.sdk.provider")
  if not provider.is_available() then
    vim.notify(
      "Emissary: claude_agent_sdk not found. Set config.sdk_path or add to runtimepath.",
      vim.log.levels.WARN
    )
  end
end

--- Create user commands
-- Note: Commands are defined in plugin/emissary.lua for lazy.nvim auto-detection
-- This function is kept for compatibility but commands are already registered
function M._create_commands()
  -- Commands are defined in plugin/emissary.lua so lazy.nvim can auto-detect them
  -- Nothing to do here
end

--- Setup keymaps based on configuration
function M._setup_keymaps()
  local config = require("emissary.config")
  local keymaps = config.get("keymaps")

  if not keymaps then
    return
  end

  -- Visual mode: send selection with instruction from command line
  if keymaps.visual then
    vim.keymap.set("v", keymaps.visual, function()
      -- Exit visual mode first to capture selection
      local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
      vim.api.nvim_feedkeys(esc, "x", false)
      -- Prompt for instruction via command line
      vim.ui.input({ prompt = "Emissary instruction: " }, function(input)
        if input and #input > 0 then
          local visual_replace = require("emissary.ops.visual_replace")
          local geo = require("emissary.geo")
          local range = geo.Range.from_visual_selection()
          if range then
            visual_replace.execute({
              bufnr = vim.api.nvim_get_current_buf(),
              range = range,
              instruction = input,
            })
          end
        end
      end)
    end, { desc = "Send visual selection to Claude Code" })
  end

  -- Visual mode: send selection with floating prompt
  if keymaps.visual_prompt then
    vim.keymap.set("v", keymaps.visual_prompt, function()
      local visual_replace = require("emissary.ops.visual_replace")
      visual_replace.with_prompt()
    end, { desc = "Send visual selection to Claude Code with prompt" })
  end

  -- Normal mode: cancel all operations
  if keymaps.cancel then
    vim.keymap.set("n", keymaps.cancel, function()
      M.cancel_all()
    end, { desc = "Cancel all Emissary operations" })
  end

  -- Normal mode: line instruction
  if keymaps.line then
    vim.keymap.set("n", keymaps.line, function()
      local count = vim.v.count1
      -- Capture buffer and cursor BEFORE vim.ui.input (which may change current buffer)
      local bufnr = vim.api.nvim_get_current_buf()
      local cursor = vim.api.nvim_win_get_cursor(0)
      local row = cursor[1]
      vim.ui.input({ prompt = "Emissary line instruction: " }, function(input)
        if input and #input > 0 then
          local line_replace = require("emissary.ops.line_replace")
          line_replace.from_position(bufnr, row, count, input)
        end
      end)
    end, { desc = "Apply instruction to current line(s)" })
  end

  -- Visual mode: implement function stub
  if keymaps.implement then
    vim.keymap.set("v", keymaps.implement, function()
      local implement = require("emissary.ops.implement")
      implement.from_visual_selection()
    end, { desc = "Implement selected function stub" })
  end

  -- Normal mode: scan for @llm tags
  if keymaps.scan then
    vim.keymap.set("n", keymaps.scan, function()
      local tag_scan = require("emissary.ops.tag_scan")
      tag_scan.execute_all(vim.api.nvim_get_current_buf())
    end, { desc = "Scan and implement all @llm tags" })
  end
end

--- Cancel all active operations
function M.cancel_all()
  local state = require("emissary.state")
  local cleanup = require("emissary.ops.cleanup")
  local count = state.count()

  if count == 0 then
    vim.notify("Emissary: No active operations", vim.log.levels.INFO)
    return
  end

  cleanup.cleanup_all()
  vim.notify(string.format("Emissary: Cancelled %d operation(s)", count), vim.log.levels.INFO)
end

--- Show status of active operations
function M.show_status()
  local state = require("emissary.state")
  local operations = state.get_all()

  if #operations == 0 then
    vim.notify("Emissary: No active operations", vim.log.levels.INFO)
    return
  end

  local lines = { "Emissary Operations:" }
  for _, op in ipairs(operations) do
    table.insert(lines, "  " .. op:summary())
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

--- Get count of active operations
-- @return number
function M.operation_count()
  local state = require("emissary.state")
  return state.count()
end

--- Check if SDK is available
-- @return boolean
function M.is_available()
  local provider = require("emissary.sdk.provider")
  return provider.is_available()
end

-- Re-export commonly used modules for convenience
M.config = require("emissary.config")
M.state = require("emissary.state")

return M
