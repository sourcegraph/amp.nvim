# Amp Neovim Plugin

This plugin allows the [Amp CLI](https://ampcode.com/manual#cli) to see the file you currently have open in your Neovim instance, along with your cursor position and your text selection.


https://github.com/user-attachments/assets/3a5f136f-7b0a-445f-90be-b4e5b28a7e82


## Installation

Install the plugin by adding this code to your lazy.vim config:

```lua
  -- Amp Plugin
{
  "sourcegraph/amp.nvim",
  branch = "main", 
  lazy = false,
  opts = { auto_start = true, log_level = "info" },
}
```

Once installed, run `amp --ide`.

## Development

Uses `stylua` for general formatting, and `lua-language-server` for linting.

```bash
stylua .
nvim --headless --clean -c ':!lua-language-server --check .' -c 'qa'
```

## Features

- Notify Amp about currently open file (you need to select a file, there's currently no initial sync)
- Notify Amp about selected code
- Notify Amp about Neovim diagnostics
- Send messages to the Amp agent
- Read and edit files through the Nvim buffer (while also writing to disk)
  - We talked about changing this to writing to disk by default, and then telling nvim to reload. That may however cause issues with fresh buffers that have no file yet. Let us know what you think!

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
```

## Feature Ideas

- Better reconnect: Nvim users are much more likely to reopen their IDE than JetBrains users. Because of that, we should check if we can automatically reconnect to an IDE in the same path that we had the last connection with.
- When I ask Amp to show me a particular section of code, it would be nice if Amp could open that file and select the code for me.
- Should we keep the code selection when moving between tab? Currently you can't switch to a split terminal if you don't want to loose the selection, i.e. making the built in terminal unfeasible for code selection.

## Running on Linux

The directory for lockfiles is currently hard-coded to a mac variant. Let us know if you run into problems on Linux with that.

```lua
  local home = vim.fn.expand("~")
  local lock_dir = home .. "/.local/share/amp/ide"
  local lockfile_path = lock_dir .. "/" .. tostring(port) .. ".json"
```
