--- Emissary configuration defaults
-- @module emissary.config

local M = {}

--- Default configuration values
M.defaults = {
  -- SDK settings
  permission_mode = "acceptEdits",
  allowed_tools = { "Read", "Write", "Edit", "Glob", "Grep" },
  max_turns = 10,
  timeout = 60,  -- Operation timeout in seconds (0 = no timeout)

  -- Prompt settings
  full_file_context = true, -- Send full file contents vs just context lines

  -- Keymaps (set to false to disable)
  keymaps = {
    visual = "<leader>ar",       -- Send visual selection with instruction
    visual_prompt = "<leader>ap", -- Send with floating prompt window
    cancel = "<leader>ax",       -- Cancel all operations
    line = "<leader>al",         -- Normal mode line instruction
    implement = "<leader>ai",    -- Implement function stub (visual mode)
    scan = "<leader>as",         -- Scan for @llm tags
  },

  -- UI settings
  ui = {
    spinner_interval = 80,       -- Spinner update interval in ms
    show_preview = true,         -- Show preview of streaming content
    preview_max_lines = 3,       -- Max lines to show in preview
  },

  -- Path to claude-agent-sdk-lua (if not in runtimepath)
  sdk_path = nil,

  -- Tag scanning settings
  tag_scan = {
    pattern = "@llm%s+(.+)",    -- Lua pattern for tag extraction
    remove_after = true,        -- Remove tag after successful implementation
  },

  -- Debug settings
  debug = false,

  -- Logging settings
  log = {
    level = "INFO",  -- DEBUG, INFO, WARN, ERROR
    file = nil,      -- nil = auto (~/.local/state/nvim/emissary.log)
  },
}

--- Current configuration (populated by setup())
M.current = vim.deepcopy(M.defaults)

--- Merge user config with defaults
-- @param user_config table|nil User configuration
-- @return table Merged configuration
function M.setup(user_config)
  M.current = vim.tbl_deep_extend("force", M.defaults, user_config or {})
  return M.current
end

--- Get a config value by key path
-- @param path string Dot-separated path (e.g., "keymaps.visual")
-- @return any The config value
function M.get(path)
  local keys = vim.split(path, ".", { plain = true })
  local value = M.current
  for _, key in ipairs(keys) do
    if type(value) ~= "table" then
      return nil
    end
    value = value[key]
  end
  return value
end

return M
