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

## Commands

### Message Commands

- `:Amp <your message>` - Send a message directly to the Amp agent
  - Preserves visual selections, so you can select code and send messages about it
  - Example: Select some code, then `:Amp explain this function`

- `:AmpDraft` - Open a scratch buffer to compose a message
  - Opens in a horizontal split for writing longer messages
  - Use `:AmpSendDraft` to send the message and close the buffer

### Custom Commands

You can create custom commands using the Lua API:

```lua
-- Custom command to open draft in vertical split with specific width
vim.api.nvim_create_user_command("AmpDraftV", function()
  require("amp.message").open_draft_vertical(60, "right")  -- 60 columns wide on right
end, { desc = "Open Amp draft message in vertical split" })

-- Custom command to open draft on left side
vim.api.nvim_create_user_command("AmpDraftLeft", function()
  require("amp.message").open_draft_vertical(50, "left")  -- 50 columns on left
end, { desc = "Open Amp draft message on left side" })

-- Custom command to open draft in horizontal split with specific height  
vim.api.nvim_create_user_command("AmpDraftH", function()
  require("amp.message").open_draft_horizontal(10, "bottom")  -- 10 rows at bottom
end, { desc = "Open Amp draft message in horizontal split" })

-- Custom command to open draft at top
vim.api.nvim_create_user_command("AmpDraftTop", function()
  require("amp.message").open_draft_horizontal(8, "top")  -- 8 rows at top
end, { desc = "Open Amp draft message at top" })

-- Custom keybinding to send a predefined message
vim.keymap.set("v", "<leader>ae", function()
  vim.cmd("AmpSendMessage explain this code")
end, { desc = "Ask Amp to explain selected code" })
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
