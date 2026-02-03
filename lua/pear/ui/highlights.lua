--- Highlight group definitions
-- @module pear.ui.highlights

local M = {}

--- Define highlight groups for Pear
function M.setup()
  -- Status line spinner/text
  vim.api.nvim_set_hl(0, "PearStatus", {
    fg = "#7aa2f7",  -- Blue
    italic = true,
    default = true,
  })

  -- Status when completing
  vim.api.nvim_set_hl(0, "PearStatusComplete", {
    fg = "#9ece6a",  -- Green
    italic = true,
    default = true,
  })

  -- Status on error
  vim.api.nvim_set_hl(0, "PearStatusError", {
    fg = "#f7768e",  -- Red
    italic = true,
    default = true,
  })

  -- Preview text (streaming content)
  vim.api.nvim_set_hl(0, "PearPreview", {
    fg = "#565f89",  -- Dim
    italic = true,
    default = true,
  })

  -- Active selection being processed
  vim.api.nvim_set_hl(0, "PearActiveRegion", {
    bg = "#292e42",  -- Subtle background
    default = true,
  })

  -- Prompt window title
  vim.api.nvim_set_hl(0, "PearPromptTitle", {
    fg = "#bb9af7",  -- Purple
    bold = true,
    default = true,
  })

  -- Prompt window border
  vim.api.nvim_set_hl(0, "PearPromptBorder", {
    fg = "#565f89",  -- Dim
    default = true,
  })
end

return M
