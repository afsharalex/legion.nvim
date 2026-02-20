# Legion

AI-powered code editing for Neovim using Claude Code.

If you use OpenCode, check out [99](https://github.com/ThePrimeagen/99) instead.

## Features

- **Visual Selection**: Highlight code, give instructions, get AI modifications
- **Line Editing**: Edit current line(s) with natural language
- **Function Implementation**: Generate function bodies from stubs
- **Batch Processing**: Use `@llm` tags for bulk implementations
- **Non-blocking**: Continue editing while AI works
- **Streaming**: See results as they arrive

## Quick Start

1. Install with your package manager
2. Add to config: `require("legion").setup()`
3. Select code, press `<leader>ar`, type instruction

## Commands

| Command | Keymap | Description |
|---------|--------|-------------|
| `LgnVisual` | `<leader>ar` | Replace selection with AI |
| `LgnVisualPrompt` | `<leader>ap` | Replace with floating prompt |
| `LgnLine` | `<leader>al` | Edit current line(s) |
| `LgnImplement` | `<leader>ai` | Implement function stub |
| `LgnScan` | `<leader>as` | Process all `@llm` tags |
| `LgnCancel` | `<leader>ax` | Cancel operations |
| `LgnStatus` | - | Show operation status |

## Requirements

- Neovim 0.9+
- Claude Code CLI installed and authenticated
- [claude-agent-sdk-lua](https://github.com/afsharalex/claude-agent-sdk-lua)

## Installation

### lazy.nvim

```lua
{
  "afsharalex/legion.nvim",
  dependencies = {
    "afsharalex/claude-agent-sdk-lua",
  },
  config = function()
    require("legion").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "afsharalex/legion.nvim",
  requires = { "afsharalex/claude-agent-sdk-lua" },
  config = function()
    require("legion").setup()
  end,
}
```

## Configuration

```lua
require("legion").setup({
  -- SDK settings
  permission_mode = "acceptEdits",
  max_turns = 10,
  timeout = 60,  -- seconds (0 = no timeout)

  -- Context settings
  full_file_context = true,  -- Send full file vs just selection

  -- Keymaps (set to false to disable individual keymaps)
  keymaps = {
    visual = "<leader>ar",        -- Visual selection replace
    visual_prompt = "<leader>ap", -- With floating prompt
    cancel = "<leader>ax",        -- Cancel all operations
    line = "<leader>al",          -- Line instruction
    implement = "<leader>ai",     -- Implement function stub
    scan = "<leader>as",          -- Scan for @llm tags
  },

  -- UI settings
  ui = {
    spinner_interval = 80,
    show_preview = true,
    preview_max_lines = 3,
  },

  -- Tag scanning
  tag_scan = {
    pattern = "@llm%s+(.+)",  -- Lua pattern for tag extraction
    remove_after = true,       -- Remove tag after implementation
  },

  -- Logging
  log = {
    level = "INFO",  -- DEBUG, INFO, WARN, ERROR
    file = nil,      -- nil = ~/.local/state/nvim/legion.log
  },
})
```

## Documentation

- [Getting Started](docs/getting-started.md) - Learn the basics
- [Usage Guide](docs/usage-guide.md) - Specific workflows

## Inspiration

This plugin was heavily inspired by ThePrimeagen's [99](https://github.com/ThePrimeagen/99), taking a slightly different approach and using Claude Code instead of OpenCode. Give his plugin a look as well.

## License

MIT
