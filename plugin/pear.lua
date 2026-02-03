-- Pear plugin commands
-- These are defined here so lazy.nvim can auto-detect them

if vim.g.loaded_pear then
  return
end
vim.g.loaded_pear = true

-- Visual selection commands
vim.api.nvim_create_user_command("PearVisual", function(opts)
  require("pear") -- Ensure setup runs
  local visual_replace = require("pear.ops.visual_replace")
  visual_replace.from_visual_selection(opts.args)
end, {
  range = true,
  nargs = "*",
  desc = "Send visual selection to Claude Code with instruction",
})

vim.api.nvim_create_user_command("PearVisualPrompt", function()
  require("pear")
  local visual_replace = require("pear.ops.visual_replace")
  visual_replace.with_prompt()
end, {
  range = true,
  desc = "Send visual selection to Claude Code with prompt window",
})

-- Line replace command
vim.api.nvim_create_user_command("PearLine", function(opts)
  require("pear")
  local line_replace = require("pear.ops.line_replace")
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
vim.api.nvim_create_user_command("PearImplement", function()
  require("pear")
  local implement = require("pear.ops.implement")
  implement.from_visual_selection()
end, {
  range = true,
  desc = "Implement selected function stub",
})

-- Tag scan command
vim.api.nvim_create_user_command("PearScan", function()
  require("pear")
  local tag_scan = require("pear.ops.tag_scan")
  tag_scan.execute_all(vim.api.nvim_get_current_buf())
end, {
  desc = "Scan and implement all @llm tags in current buffer",
})

-- Utility commands
vim.api.nvim_create_user_command("PearCancel", function()
  local pear = require("pear")
  pear.cancel_all()
end, {
  desc = "Cancel all Pear operations",
})

vim.api.nvim_create_user_command("PearStatus", function()
  local pear = require("pear")
  pear.show_status()
end, {
  desc = "Show active Pear operations",
})
