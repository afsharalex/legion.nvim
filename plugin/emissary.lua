-- Emissary plugin commands
-- These are defined here so lazy.nvim can auto-detect them

if vim.g.loaded_emissary then
  return
end
vim.g.loaded_emissary = true

-- Visual selection commands
vim.api.nvim_create_user_command("EmiVisual", function(opts)
  require("emissary") -- Ensure setup runs
  local visual_replace = require("emissary.ops.visual_replace")
  visual_replace.from_visual_selection(opts.args)
end, {
  range = true,
  nargs = "*",
  desc = "Send visual selection to Claude Code with instruction",
})

vim.api.nvim_create_user_command("EmiVisualPrompt", function()
  require("emissary")
  local visual_replace = require("emissary.ops.visual_replace")
  visual_replace.with_prompt()
end, {
  range = true,
  desc = "Send visual selection to Claude Code with prompt window",
})

-- Line replace command
vim.api.nvim_create_user_command("EmiLine", function(opts)
  require("emissary")
  local line_replace = require("emissary.ops.line_replace")
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
vim.api.nvim_create_user_command("EmiImplement", function()
  require("emissary")
  local implement = require("emissary.ops.implement")
  implement.from_visual_selection()
end, {
  range = true,
  desc = "Implement selected function stub",
})

-- Tag scan command
vim.api.nvim_create_user_command("EmiScan", function()
  require("emissary")
  local tag_scan = require("emissary.ops.tag_scan")
  tag_scan.execute_all(vim.api.nvim_get_current_buf())
end, {
  desc = "Scan and implement all @llm tags in current buffer",
})

-- Utility commands
vim.api.nvim_create_user_command("EmiCancel", function()
  local emissary = require("emissary")
  emissary.cancel_all()
end, {
  desc = "Cancel all Emissary operations",
})

vim.api.nvim_create_user_command("EmiStatus", function()
  local emissary = require("emissary")
  emissary.show_status()
end, {
  desc = "Show active Emissary operations",
})
