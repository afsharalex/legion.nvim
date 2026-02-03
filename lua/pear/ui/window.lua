--- Floating window for prompts
-- @module pear.ui.window

local M = {}

--- Capture user input in a floating window
-- @param opts table Options
-- @param opts.title string Window title
-- @param opts.callback function(input) Called with user input or nil if cancelled
function M.capture_input(opts)
  opts = opts or {}
  local title = opts.title or "Pear Prompt"
  local callback = opts.callback or function() end

  -- Create buffer for input
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "pear_prompt"

  -- Calculate window size and position
  local width = math.min(80, vim.o.columns - 10)
  local height = 3
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Window options
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  }

  -- Create window
  local win = vim.api.nvim_open_win(buf, true, win_opts)

  -- Set window highlights
  vim.wo[win].winhl = "Normal:Normal,FloatBorder:PearPromptBorder,FloatTitle:PearPromptTitle"
  vim.wo[win].cursorline = false

  -- Enter insert mode
  vim.cmd("startinsert")

  -- Track if callback was called
  local called = false
  local function finish(result)
    if called then
      return
    end
    called = true

    -- Close window if still open
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end

    -- Exit insert mode
    vim.cmd("stopinsert")

    -- Call callback
    vim.schedule(function()
      callback(result)
    end)
  end

  -- Key mappings
  local kopts = { buffer = buf, noremap = true, silent = true }

  -- Enter to submit
  vim.keymap.set("i", "<CR>", function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local input = vim.trim(table.concat(lines, "\n"))
    if #input > 0 then
      finish(input)
    end
  end, kopts)

  -- Escape to cancel
  vim.keymap.set("i", "<Esc>", function()
    finish(nil)
  end, kopts)

  vim.keymap.set("n", "<Esc>", function()
    finish(nil)
  end, kopts)

  vim.keymap.set("n", "q", function()
    finish(nil)
  end, kopts)

  -- Ctrl-C to cancel
  vim.keymap.set("i", "<C-c>", function()
    finish(nil)
  end, kopts)

  -- Handle window close
  vim.api.nvim_create_autocmd("WinClosed", {
    buffer = buf,
    once = true,
    callback = function()
      finish(nil)
    end,
  })
end

--- Show a brief notification message
-- @param msg string Message to show
-- @param level number|nil Vim log level (default: INFO)
function M.notify(msg, level)
  level = level or vim.log.levels.INFO
  vim.notify(msg, level, { title = "Pear" })
end

return M
