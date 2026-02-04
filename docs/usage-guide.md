# Emissary Usage Guide

Task-oriented guides for common Emissary workflows.

## How to Replace Selected Code with AI

1. Enter visual mode (`v`, `V`, or `<C-v>`)
2. Select the code you want to modify
3. Press `<leader>ar`
4. Enter your instruction when prompted
5. Wait for the replacement

**Alternative with floating prompt:**

1. Select code in visual mode
2. Press `<leader>ap`
3. Type in the floating window (multi-line supported)
4. Press `<Esc>` then `<CR>` to submit

## How to Edit the Current Line

1. Position cursor on the line to edit
2. Press `<leader>al`
3. Enter your instruction
4. Line is replaced with AI-generated content

**Edit multiple lines:**

1. Position cursor on the first line
2. Type a count (e.g., `3`)
3. Press `<leader>al`
4. Enter instruction (applies to 3 lines)

## How to Implement a Function Stub

1. Write a function signature or stub:
   ```python
   def calculate_tax(amount, rate):
       pass
   ```
2. Select the entire function in visual mode
3. Press `<leader>ai`
4. AI generates the implementation

## How to Batch-Implement with @llm Tags

1. Add `@llm` tags to your code:
   ```python
   # @llm implement binary search
   def binary_search(arr, target):
       pass
   ```
2. Press `<leader>as` to scan the buffer
3. Each tagged element is implemented in sequence (bottom-to-top)
4. Tags are removed after successful implementation

**Custom tag patterns:**

```lua
require("emissary").setup({
  tag_scan = {
    pattern = "@ai%s+(.+)",  -- Use @ai instead of @llm
  },
})
```

## How to Cancel Operations

**Cancel all operations:**

Press `<leader>ax` or run `:EmiCancel`

**Cancel specific operation:**

Currently, cancellation applies to all active operations.

## How to Configure Keybindings

**Change default keymaps:**

```lua
require("emissary").setup({
  keymaps = {
    visual = "<leader>cr",        -- Change to <leader>cr
    visual_prompt = "<leader>cp",
    cancel = "<leader>cc",
    line = "<leader>cl",
    implement = "<leader>ci",
    scan = "<leader>cs",
  },
})
```

**Disable specific keymaps:**

```lua
require("emissary").setup({
  keymaps = {
    visual = "<leader>ar",
    visual_prompt = false,  -- Disable this keymap
    cancel = "<leader>ax",
    line = false,           -- Disable this keymap
    implement = "<leader>ai",
    scan = "<leader>as",
  },
})
```

## How to Customize Context

**Full file context (default):**

```lua
require("emissary").setup({
  full_file_context = true,
})
```

AI sees the entire file for better understanding.

**Selection only:**

```lua
require("emissary").setup({
  full_file_context = false,
})
```

Faster, but AI has less context.

## How to Adjust Timeouts

```lua
require("emissary").setup({
  timeout = 120,  -- 2 minutes
  -- timeout = 0,  -- No timeout
})
```

## How to Debug Issues

**Enable debug logging:**

```lua
require("emissary").setup({
  log = {
    level = "DEBUG",
  },
})
```

**View logs:**

```bash
tail -f ~/.local/state/nvim/emissary.log
```

**Check SDK availability:**

```vim
:lua print(require("emissary").is_available())
```

**Check operation count:**

```vim
:lua print(require("emissary").operation_count())
```

## How to Use Commands Directly

All operations are available as commands:

| Command | Usage |
|---------|-------|
| `:EmiVisual <instruction>` | Replace selection with instruction |
| `:EmiVisualPrompt` | Replace with floating prompt |
| `:[count]EmiLine <instruction>` | Edit current line(s) |
| `:EmiImplement` | Implement selected stub |
| `:EmiScan` | Process all @llm tags |
| `:EmiCancel` | Cancel all operations |
| `:EmiStatus` | Show active operations |

**Example:**

```vim
:'<,'>EmiVisual add error handling
```

## How to Handle Errors

**SDK not found:**

Ensure `claude-agent-sdk-lua` is installed and in your runtimepath.

```lua
require("emissary").setup({
  sdk_path = "/path/to/claude-agent-sdk-lua",
})
```

**Authentication errors:**

Run `claude auth login` in your terminal.

**Empty responses:**

- Check your instruction is clear
- Increase timeout if operation is complex
- Enable debug logging to see full prompt
