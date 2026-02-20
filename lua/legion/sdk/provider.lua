--- Wrapper around claude_agent_sdk
-- @module legion.sdk.provider

local config = require("legion.config")
local log = require("legion.log")

local M = {}

--- Cached SDK module
local sdk = nil

--- Load the SDK module
-- @return table|nil SDK module or nil if not available
local function load_sdk()
  if sdk then
    return sdk
  end

  -- Try loading from configured path first
  local sdk_path = config.get("sdk_path")
  if sdk_path then
    local ok, module = pcall(function()
      -- Add to package.path if not already there
      local path_pattern = sdk_path .. "/lua/?.lua"
      if not package.path:find(path_pattern, 1, true) then
        package.path = path_pattern .. ";" .. sdk_path .. "/lua/?/init.lua;" .. package.path
      end
      return require("claude_agent_sdk")
    end)
    if ok then
      sdk = module
      return sdk
    end
  end

  -- Try loading from runtimepath
  local ok, module = pcall(require, "claude_agent_sdk")
  if ok then
    sdk = module
    return sdk
  end

  return nil
end

--- Check if SDK is available
-- @return boolean
function M.is_available()
  return load_sdk() ~= nil
end

--- Get the SDK module
-- @return table|nil
function M.get_sdk()
  return load_sdk()
end

--- Create SDK client options
-- @param opts table|nil Additional options
-- @return table ClaudeAgentOptions
function M.create_options(opts)
  opts = opts or {}

  local sdk_module = load_sdk()
  if not sdk_module then
    error("Claude Agent SDK not available")
  end

  local cfg = config.current

  return sdk_module.ClaudeAgentOptions.new({
    permission_mode = opts.permission_mode or cfg.permission_mode,
    allowed_tools = opts.allowed_tools or cfg.allowed_tools,
    max_turns = opts.max_turns or cfg.max_turns,
  })
end

--- Create a new SDK client
-- @param opts table|nil Options for ClaudeAgentOptions
-- @return table|nil ClaudeSDKClient or nil on error
function M.create_client(opts)
  local sdk_module = load_sdk()
  if not sdk_module then
    return nil, "Claude Agent SDK not available"
  end

  local options = M.create_options(opts)
  return sdk_module.ClaudeSDKClient.new(options)
end

--- Start a query with streaming callbacks
-- All callbacks are wrapped with vim.schedule() for UI safety.
-- @param opts table Query options
-- @param opts.prompt string The prompt to send
-- @param opts.on_message function(message) Called for each message
-- @param opts.on_text function(text) Called for accumulated text from AssistantMessages
-- @param opts.on_done function(result) Called when complete
-- @param opts.on_error function(err) Called on error
-- @return table|nil Client for cancellation, or nil on error
function M.start_query(opts)
  local sdk_module = load_sdk()
  if not sdk_module then
    log.error("Claude Agent SDK not available")
    if opts.on_error then
      vim.schedule(function()
        opts.on_error("Claude Agent SDK not available")
      end)
    end
    return nil
  end

  local prompt = opts.prompt
  local on_message = opts.on_message or function() end
  local on_text = opts.on_text or function() end
  local on_done = opts.on_done or function() end
  local on_error = opts.on_error or function() end

  -- Create client with stderr capture
  local client_opts = opts.sdk_options or {}
  local cfg = config.current

  -- Accumulated stderr for error reporting
  local accumulated_stderr = ""

  local sdk_opts = {
    permission_mode = client_opts.permission_mode or cfg.permission_mode,
    allowed_tools = client_opts.allowed_tools or cfg.allowed_tools,
    max_turns = client_opts.max_turns or cfg.max_turns,
    stderr = function(data)
      if data and #data > 0 then
        log.debug("[stderr] " .. data)
        accumulated_stderr = accumulated_stderr .. data
      end
    end,
  }

  -- Add cwd if provided
  if client_opts.cwd then
    sdk_opts.cwd = client_opts.cwd
    log.debug("Using cwd: " .. client_opts.cwd)
  end

  local options = sdk_module.ClaudeAgentOptions.new(sdk_opts)

  local client = sdk_module.ClaudeSDKClient.new(options)

  -- Accumulated text from streaming
  local accumulated_text = ""

  -- Track if we've already reported an error or completion
  local finished = false

  -- Set up message handler
  client:on_message(function(message)
    vim.schedule(function()
      -- Debug: log message type
      local msg_type = "unknown"
      if type(message) == "table" then
        msg_type = message.type or (getmetatable(message) and getmetatable(message).__type) or "table"
      end
      log.debug("Received message type: " .. msg_type)

      on_message(message)

      -- Extract text from AssistantMessage
      if sdk_module.is_assistant_message(message) then
        log.debug("Processing AssistantMessage")
        -- Debug: log content structure
        if message.content then
          log.debug("Content type: " .. type(message.content) .. ", length: " .. (type(message.content) == "table" and #message.content or 0))
          if type(message.content) == "table" then
            for i, block in ipairs(message.content) do
              local block_type = type(block) == "table" and (block.type or (getmetatable(block) and getmetatable(block).__type) or "unknown") or type(block)
              local block_text = type(block) == "table" and (block.text or "") or ""
              log.debug("  Block " .. i .. ": type=" .. tostring(block_type) .. ", text_len=" .. #block_text)
            end
          end
        else
          log.debug("Content is nil")
        end
        local text = sdk_module.get_text(message)
        log.debug("Extracted text length: " .. (text and #text or 0))
        if text and #text > 0 then
          accumulated_text = accumulated_text .. text
          on_text(accumulated_text)
        end
      end

      -- Check for result message
      if sdk_module.is_result_message(message) then
        finished = true
        log.info("Query completed successfully")
        on_done(message)
      end
    end)
  end)

  -- Set up error handler
  client:on_error(function(err)
    vim.schedule(function()
      if finished then
        return
      end
      finished = true

      -- Enhance error with stderr if available
      local enhanced_err = err
      if type(err) == "table" then
        err.stderr = accumulated_stderr
      elseif type(err) == "string" and #accumulated_stderr > 0 then
        enhanced_err = {
          message = err,
          stderr = accumulated_stderr,
        }
      end

      log.error("SDK error: " .. M.format_error(enhanced_err))
      on_error(enhanced_err)
    end)
  end)

  -- Set up exit handler to capture non-zero exit codes
  if client.on_exit then
    client:on_exit(function(code, signal)
      vim.schedule(function()
        if finished then
          return
        end

        if code ~= 0 then
          finished = true
          local msg = string.format("CLI exited with code %s", tostring(code))
          if signal then
            msg = msg .. " (signal " .. tostring(signal) .. ")"
          end

          local exit_err = {
            type = "exit",
            code = code,
            signal = signal,
            message = msg,
            stderr = accumulated_stderr,
          }

          log.error(msg)
          if #accumulated_stderr > 0 then
            log.error("stderr: " .. accumulated_stderr)
          end

          on_error(exit_err)
        end
      end)
    end)
  end

  log.info("Starting query")
  log.debug("Prompt: " .. string.sub(prompt, 1, 200) .. (#prompt > 200 and "..." or ""))

  -- Connect and send prompt
  client:connect(prompt, function(err)
    if err then
      vim.schedule(function()
        if finished then
          return
        end
        finished = true
        log.error("Connection error: " .. M.format_error(err))
        on_error(err)
      end)
    end
  end)

  return client
end

--- Format an error for logging/display
-- @param err any The error object
-- @return string
function M.format_error(err)
  if err == nil then
    return "Unknown error"
  end

  if type(err) == "string" then
    return err
  end

  if type(err) == "table" then
    local parts = {}

    if err.message then
      table.insert(parts, tostring(err.message))
    elseif err.type then
      table.insert(parts, "Error type: " .. tostring(err.type))
    end

    if err.code then
      table.insert(parts, "code=" .. tostring(err.code))
    end

    if err.exit_code then
      table.insert(parts, "exit_code=" .. tostring(err.exit_code))
    end

    if err.signal then
      table.insert(parts, "signal=" .. tostring(err.signal))
    end

    if #parts > 0 then
      return table.concat(parts, ", ")
    end
  end

  local ok, str = pcall(tostring, err)
  if ok then
    return str
  end

  return "Error (" .. type(err) .. ")"
end

--- Run a one-shot query (simpler interface)
-- @param prompt string The prompt
-- @param on_result function(text, err) Called with result text or error
function M.query(prompt, on_result)
  local sdk_module = load_sdk()
  if not sdk_module then
    vim.schedule(function()
      on_result(nil, "Claude Agent SDK not available")
    end)
    return
  end

  local cfg = config.current
  local accumulated_text = ""

  sdk_module.query({
    prompt = prompt,
    options = sdk_module.ClaudeAgentOptions.new({
      permission_mode = cfg.permission_mode,
      allowed_tools = cfg.allowed_tools,
      max_turns = cfg.max_turns,
    }),
    on_message = function(message)
      if sdk_module.is_assistant_message(message) then
        local text = sdk_module.get_text(message)
        if text and #text > 0 then
          accumulated_text = accumulated_text .. text
        end
      end
    end,
    on_done = function(result)
      vim.schedule(function()
        on_result(accumulated_text, nil)
      end)
    end,
    on_error = function(err)
      vim.schedule(function()
        on_result(nil, tostring(err))
      end)
    end,
  })
end

return M
