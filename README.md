`README.md`

# Amp Neovim Plugin

This plugin allows the [Amp CLI](https://ampcode.com/manual#cli) to see the file you currently have open in your Neovim instance, along with your cursor position and your text selection.

https://github.com/user-attachments/assets/3a5f136f-7b0a-445f-90be-b4e5b28a7e82

When installed, this plugin allows Neovim to:

- Notify Amp about currently open file
- Notify Amp about selected code
- Provide Neovim diagnostics to Amp on request
- Send messages to the Amp agent (see [Sending Messages to Amp](#sending-messages-to-amp))
- Read and edit files through the Neovim buffers
- Automatically reconnects when you restart Neovim in the same directory
- Browse and manage Amp threads with Telescope (see [Thread Management](#thread-management))
- Chat with Amp directly in Neovim buffers (see [Chat Interface](#chat-interface))

## Installation

### Using lazy.nvim

Install the plugin by adding this code to your lazy.vim config:

```lua
  -- Amp Plugin
{
  "sourcegraph/amp.nvim",
  branch = "main", 
  lazy = false,
  opts = { 
    auto_start = true, 
    log_level = "info",
    thread_response_timeout = 300000,  -- 5 minutes in milliseconds (default)
    submit_key = "<C-g>",              -- Key to send messages (default)
    sync_metadata_key = "<C-s>",       -- Key to sync thread metadata (default)
    use_stream_json = true,            -- Use --stream-json for real-time output (default: true)
  },
}
```

### Using mini.deps

```lua
local MiniDeps = require('mini.deps')
MiniDeps.add({
  source = 'sourcegraph/amp.nvim',
})

require('amp').setup({ auto_start = true, log_level = "info" })
```

### Using vim-plug

Add to your `init.vim` or `init.lua`:

```vim
Plug 'sourcegraph/amp.nvim', { 'branch': 'main' }
```

Or in Lua syntax:

```lua
vim.call('plug#begin')
vim.fn['plug#']('sourcegraph/amp.nvim', { branch = 'main' })
vim.call('plug#end')
```

Then add to your config:

```lua
require('amp').setup({ auto_start = true, log_level = "info" })
```

### Using Neovim's Native Package System

```bash
# For automatic loading on startup
git clone https://github.com/sourcegraph/amp.nvim.git \
  ~/.local/share/nvim/site/pack/plugins/start/amp.nvim

# Or for optional loading (use :packadd amp.nvim to load)
git clone https://github.com/sourcegraph/amp.nvim.git \
  ~/.local/share/nvim/site/pack/plugins/opt/amp.nvim
```

Then add to your `init.lua`:

```lua
require('amp').setup({ auto_start = true, log_level = "info" })
```

Once installed, run `amp --ide`.

## Shortcuts

Shortcuts allow you to define reusable prompts that can be quickly inserted using `#shortcut-name` syntax. When you type `#` in a chat buffer, you'll see autocomplete suggestions for all available shortcuts.

### Configuration

Define shortcuts in your nvim config:

```lua
require('amp').setup({
  auto_start = true,
  log_level = "info",
  shortcuts = {
    debug = "Please help me debug this issue. Show me step-by-step what's happening.",
    review = "Please review this code for:\n- Security issues\n- Performance problems\n- Best practices\n- Potential bugs",
    explain = "Please explain this code in detail, including what each part does and why.",
    test = "Please write comprehensive tests for this code, including edge cases.",
  }
})
```

### Usage

In any Amp chat buffer:
1. Type `#` to see all available shortcuts with autocomplete
2. Select a shortcut or continue typing to filter (e.g., `#debug`)
3. The shortcut text will be inserted into your message
4. Press `<C-g>` (or your configured `submit_key`) to send the message

Example:
```
🗨:
I'm getting an error in this function. #debug
```

When sent, this becomes:
```
I'm getting an error in this function. Please help me debug this issue. Show me step-by-step what's happening.
```

### Healthcheck
> Check the health of the plugin by running `:checkhealth amp` or to run all healthchecks run `:checkhealth`

## Sending Messages to Amp

The plugin provides a simple `send_message` function that you can use to create your own commands and workflows. Here are two example commands you can add to your configuration, one to send a quick message, and one to send the contents of a buffer (useful for drafting longer messages):

### Example Commands

```lua
-- Send a quick message to the agent
vim.api.nvim_create_user_command("AmpSend", function(opts)
  local message = opts.args
  if message == "" then
    print("Please provide a message to send")
    return
  end

  local amp_message = require("amp.message")
  amp_message.send_message(message)
end, {
  nargs = "*",
  desc = "Send a message to Amp",
})

-- Send entire buffer contents
vim.api.nvim_create_user_command("AmpSendBuffer", function(opts)
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local content = table.concat(lines, "\n")

  local amp_message = require("amp.message")
  amp_message.send_message(content)
end, {
  nargs = "?",
  desc = "Send current buffer contents to Amp",
})

-- Add selected text directly to prompt
vim.api.nvim_create_user_command("AmpPromptSelection", function(opts)
  local lines = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
  local text = table.concat(lines, "\n")

  local amp_message = require("amp.message")
  amp_message.send_to_prompt(text)
end, {
  range = true,
  desc = "Add selected text to Amp prompt",
})

-- Add file+selection reference to prompt
vim.api.nvim_create_user_command("AmpPromptRef", function(opts)
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname == "" then
    print("Current buffer has no filename")
    return
  end

  local relative_path = vim.fn.fnamemodify(bufname, ":.")
  local ref = "@" .. relative_path
  if opts.line1 ~= opts.line2 then
    ref = ref .. "#L" .. opts.line1 .. "-" .. opts.line2
  elseif opts.line1 > 1 then
    ref = ref .. "#L" .. opts.line1
  end

  local amp_message = require("amp.message")
  amp_message.send_to_prompt(ref)
end, {
  range = true,
  desc = "Add file reference (with selection) to Amp prompt",
})
```

## Thread Management

Browse, select, and manage your Amp threads directly from Neovim using Telescope integration.

### Commands

- `:AmpThreads` - Open Telescope picker to browse all your Amp threads
  - `<CR>` - Open selected thread in a chat buffer
  - `<C-o>` - Open selected thread in your browser
  - `<C-n>` - Create a new thread

### Requirements

Thread management requires [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) to be installed.

## Chat Interface

Interact with Amp directly in Neovim buffers, similar to parrot.nvim. Type your messages, send them to Amp, and receive responses in real-time.

### Commands

- `:AmpChat` - Open a new chat buffer for a new thread
- `:AmpChatThread <thread-id>` - Open a chat buffer for an existing thread

### Usage

Once in a chat buffer:

- Type your message after the `🗨:` separator
- Press `<C-g>` in normal or insert mode to send the message (configurable via `submit_key`)
- Press `<C-s>` in normal or insert mode to sync metadata (visibility/topic) without sending a message (configurable via `sync_metadata_key`)
- Press `i` in normal mode to jump to input mode
- Press `q` in normal mode to close the chat buffer

Messages and responses appear in the buffer in real-time, formatted in Markdown.

### Streaming Mode

By default, the plugin uses `--stream-json` mode which provides structured JSON output from the Amp CLI. This enables better parsing and handling of Claude's responses.

You can disable this and use the traditional plain text mode by setting `use_stream_json = false` in your config:

```lua
require('amp').setup({
  use_stream_json = false,  -- Use plain text output instead of JSON
})
```

### Thread Metadata

At the top of each chat buffer, you can configure:

- `# topic:` - The thread name/title
- `# visibility:` - Thread visibility (`private`, `public`, `unlisted`, `workspace`, or `group`)

Metadata is automatically synced when you send a message, or you can manually sync it anytime with `<C-s>`.

### Example Workflow

1. Run `:AmpThreads` to browse your existing threads
2. Select a thread with `<CR>` to open it in a chat buffer
3. Type your message and press `<C-g>` (or your configured `submit_key`) to send
4. View Amp's response as it streams in
5. Continue the conversation or press `q` to close

Alternatively, start a new conversation:

1. Run `:AmpChat` to create a new thread
2. Type your first message
3. Press `<C-g>` (or your configured `submit_key`) to send and start the conversation

## Feature Ideas

Do you have a feature request or an idea? Submit an issue in this repo!

## Development

Uses `stylua` for general formatting, and `lua-language-server` for linting.

```bash
stylua .
nvim --headless --clean -c ':!lua-language-server --check .' -c 'qa'
```

## Cross-Platform Support

The plugin uses the same lockfile directory pattern as the main Amp repository:

- **Windows & macOS**: `~/.local/share/amp/ide`
- **Linux**: `$XDG_DATA_HOME/amp/ide` or `~/.local/share/amp/ide`

You can override the data directory by setting the `AMP_DATA_HOME` environment variable for testing or custom setups.

## Logging

The amp.nvim plugin logs to `~/.cache/nvim/amp.log`.

## Contributing

Contributors should follow the [Sourcegraph Community Code of Conduct](https://sourcegraph.notion.site/Sourcegraph-Community-Code-of-Conduct-c7cef6b270c84fb2882808d4d82995dd).
