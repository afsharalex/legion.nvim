-- Legion plugin commands
-- These are defined here so lazy.nvim can auto-detect them

if vim.g.loaded_legion then
  return
end
vim.g.loaded_legion = true

-- Visual selection commands
vim.api.nvim_create_user_command("LgnVisual", function(opts)
  require("legion") -- Ensure setup runs
  local visual_replace = require("legion.ops.visual_replace")
  visual_replace.from_visual_selection(opts.args)
end, {
  range = true,
  nargs = "*",
  desc = "Send visual selection to Claude Code with instruction",
})

vim.api.nvim_create_user_command("LgnVisualPrompt", function()
  require("legion")
  local visual_replace = require("legion.ops.visual_replace")
  visual_replace.with_prompt()
end, {
  range = true,
  desc = "Send visual selection to Claude Code with prompt window",
})

-- Line replace command
vim.api.nvim_create_user_command("LgnLine", function(opts)
  require("legion")
  local line_replace = require("legion.ops.line_replace")
  local count = opts.count
  if count == 0 then
    count = 1
  end
  line_replace.from_current_line(opts.args, count)
end, {
  nargs = "*",
  count = true,
  desc = "Apply instruction to current line(s)",
})

-- Implement function command
vim.api.nvim_create_user_command("LgnImplement", function()
  require("legion")
  local implement = require("legion.ops.implement")
  implement.from_visual_selection()
end, {
  range = true,
  desc = "Implement selected function stub",
})

-- Tag scan command
vim.api.nvim_create_user_command("LgnScan", function()
  require("legion")
  local tag_scan = require("legion.ops.tag_scan")
  tag_scan.execute_all(vim.api.nvim_get_current_buf())
end, {
  desc = "Scan and implement all @llm tags in current buffer",
})

-- Utility commands
vim.api.nvim_create_user_command("LgnCancel", function()
  local legion = require("legion")
  legion.cancel_all()
end, {
  desc = "Cancel all Legion operations",
})

vim.api.nvim_create_user_command("LgnStatus", function()
  local legion = require("legion")
  legion.show_status()
end, {
  desc = "Show active Legion operations",
})
