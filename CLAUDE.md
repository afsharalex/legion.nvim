# Emissary - Claude Code Context

## Project Overview

Neovim plugin for AI-powered code editing via Claude Code CLI. Allows developers to select code, provide instructions, and receive AI-generated modifications without leaving Neovim.

## Architecture

```
lua/emissary/
├── init.lua              # Plugin entry, setup, keymaps
├── config.lua            # Configuration management
├── state.lua             # Global operation state tracking
├── log.lua               # Logging utilities
├── core/
│   ├── id.lua            # Unique ID generation
│   └── operation.lua     # Operation state machine (pending → running → completed/failed)
├── ops/
│   ├── visual_replace.lua # Visual selection replacement
│   ├── line_replace.lua   # Line-based editing
│   ├── implement.lua      # Function stub implementation
│   ├── tag_scan.lua       # @llm tag batch processing
│   ├── marks.lua          # Extmark range tracking
│   └── cleanup.lua        # Operation cleanup and cancellation
├── ui/
│   ├── status.lua         # Spinner and status display
│   ├── window.lua         # Floating window management
│   └── highlights.lua     # Highlight group definitions
├── sdk/
│   └── provider.lua       # Claude CLI SDK integration
├── prompt/
│   └── builder.lua        # Prompt construction with XML structure
├── geo/
│   └── init.lua           # Point/Range geometry utilities
└── utils/
    └── git.lua            # Git root detection for cwd
```

## Key Patterns

### Extmarks for Range Tracking

Operations use extmarks to track text ranges across buffer modifications:
```lua
local marks = require("emissary.ops.marks")
op.marks = marks.mark_range(bufnr, range)
-- Later, even after other edits:
marks.replace_text(op.marks, new_text)
```

### Async Operations with Callbacks

SDK queries are non-blocking with event-driven callbacks:
```lua
provider.start_query({
  prompt = prompt,
  on_text = function(accumulated) end,
  on_done = function(result) end,
  on_error = function(err) end,
})
```

### XML-Structured Prompts

Prompts use XML tags for clear structure:
```xml
<SELECTION_CONTENT>
selected code here
</SELECTION_CONTENT>
<INSTRUCTION>
user instruction here
</INSTRUCTION>
```

### Bottom-to-Top Processing

Tag scan processes matches from bottom to top to avoid line number invalidation:
```lua
table.sort(tags, function(a, b)
  return a.range.start.row > b.range.start.row
end)
```

## Code Style

- Lua 5.1 compatible (LuaJIT)
- LDoc comments for public functions
- Module pattern with `local M = {}`
- 2-space indentation
- Snake_case for functions and variables

## Key Files

| File | Purpose |
|------|---------|
| `plugin/emissary.lua` | User command definitions for lazy.nvim detection |
| `lua/emissary/init.lua` | Main entry point, setup function |
| `lua/emissary/config.lua` | Default configuration and merging |
| `lua/emissary/core/operation.lua` | Operation lifecycle management |
| `lua/emissary/ops/marks.lua` | Extmark-based range tracking |
| `lua/emissary/sdk/provider.lua` | Claude SDK wrapper |
| `lua/emissary/prompt/builder.lua` | Prompt template construction |

## Common Tasks

### Adding a New Operation

1. Create `lua/emissary/ops/new_op.lua`
2. Use `Operation.new()` for state management
3. Use `marks.mark_range()` for text tracking
4. Use `provider.start_query()` for AI interaction
5. Add command in `plugin/emissary.lua`
6. Add keymap in `init.lua:_setup_keymaps()`

### Modifying Prompts

Edit `lua/emissary/prompt/builder.lua`. Each operation type has its own builder function.

### Debugging

Set log level to DEBUG in config:
```lua
require("emissary").setup({
  log = { level = "DEBUG" }
})
```

Logs go to `~/.local/state/nvim/emissary.log`

## Testing

Manual testing via Neovim commands. Test files in various languages to verify:
- Visual selection works correctly
- Range tracking survives concurrent edits
- Cancellation cleans up properly
- Error states are handled gracefully

## Dependencies

- `claude-agent-sdk-lua`: Claude Code CLI wrapper for Lua
- Neovim 0.9+: Required for extmark features
