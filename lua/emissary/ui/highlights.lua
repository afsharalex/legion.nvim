--- Highlight group definitions
-- @module emissary.ui.highlights

local M = {}

--- Define highlight groups for Emissary
function M.setup()
  -- Status line spinner/text
  vim.api.nvim_set_hl(0, "EmiStatus", {
    fg = "#7aa2f7",  -- Blue
    italic = true,
    default = true,
  })

  -- Status when completing
  vim.api.nvim_set_hl(0, "EmiStatusComplete", {
    fg = "#9ece6a",  -- Green
    italic = true,
    default = true,
  })

  -- Status on error
  vim.api.nvim_set_hl(0, "EmiStatusError", {
    fg = "#f7768e",  -- Red
    italic = true,
    default = true,
  })

  -- Preview text (streaming content)
  vim.api.nvim_set_hl(0, "EmiPreview", {
    fg = "#565f89",  -- Dim
    italic = true,
    default = true,
  })

  -- Active selection being processed
  vim.api.nvim_set_hl(0, "EmiActiveRegion", {
    bg = "#292e42",  -- Subtle background
    default = true,
  })

  -- Prompt window title
  vim.api.nvim_set_hl(0, "EmiPromptTitle", {
    fg = "#bb9af7",  -- Purple
    bold = true,
    default = true,
  })

  -- Prompt window border
  vim.api.nvim_set_hl(0, "EmiPromptBorder", {
    fg = "#565f89",  -- Dim
    default = true,
  })
end

return M
