# Getting Started with Emissary

This tutorial teaches you the basics of Emissary through hands-on exercises. By the end, you'll know how to use AI to edit code directly in Neovim.

## Prerequisites

Before starting, ensure you have:

1. Neovim 0.9 or later
2. Claude Code CLI installed (`npm install -g @anthropic-ai/claude-code`)
3. Claude Code authenticated (`claude auth login`)

## Installation

Add Emissary to your Neovim configuration.

**With lazy.nvim:**

```lua
{
  "afsharalex/emissary",
  dependencies = {
    "afsharalex/claude-agent-sdk-lua",
  },
  config = function()
    require("emissary").setup()
  end,
}
```

Restart Neovim after adding the plugin.

## Your First Operation: Visual Replace

Let's modify some code using AI.

**Step 1:** Create a test file.

```lua
-- test.lua
local function greet(name)
  print("Hello")
end
```

**Step 2:** Position your cursor on `print("Hello")` and press `V` to select the line.

**Step 3:** Press `<leader>ar` (leader + a + r).

**Step 4:** When prompted, type: `include the name parameter in the greeting`

**Step 5:** Watch the spinner while AI processes. The line transforms to:

```lua
print("Hello, " .. name)
```

## Line Editing

Edit lines without visual selection.

**Step 1:** Create this file:

```python
# calc.py
def add(a, b):
    pass
```

**Step 2:** Position cursor on the `pass` line.

**Step 3:** Press `<leader>al` (leader + a + l).

**Step 4:** Type: `return the sum of a and b`

**Step 5:** The line becomes:

```python
    return a + b
```

## Function Implementation

Generate complete function bodies from stubs.

**Step 1:** Create a function stub:

```javascript
// utils.js
function isPrime(n) {
  // TODO: implement
}
```

**Step 2:** Select the entire function with `V` (visual line mode), selecting all 3 lines.

**Step 3:** Press `<leader>ai` (leader + a + i).

**Step 4:** AI generates the implementation:

```javascript
function isPrime(n) {
  if (n <= 1) return false;
  if (n <= 3) return true;
  if (n % 2 === 0 || n % 3 === 0) return false;
  for (let i = 5; i * i <= n; i += 6) {
    if (n % i === 0 || n % (i + 2) === 0) return false;
  }
  return true;
}
```

## Tag Scanning

Batch-implement multiple functions using `@llm` tags.

**Step 1:** Create a file with tagged stubs:

```python
# math_utils.py

# @llm implement factorial using recursion
def factorial(n):
    pass

# @llm implement fibonacci using iteration
def fibonacci(n):
    pass
```

**Step 2:** Press `<leader>as` (leader + a + s).

**Step 3:** Both functions are implemented sequentially. Tags are removed after successful implementation.

## Canceling Operations

If an operation takes too long or you change your mind:

Press `<leader>ax` (leader + a + x) to cancel all active operations.

## Checking Status

To see what operations are currently running:

Run `:EmiStatus`

## Next Steps

Now that you know the basics:

- Read the [Usage Guide](usage-guide.md) for specific workflows
- Customize keymaps in your configuration
- Adjust timeout and context settings for your workflow
