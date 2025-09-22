# Amp Neovim Plugin

Very experimental code for a neovim plugin. Only for internal testing!

Once installed, run `amp --ide` without any other JetBrains IDEs running, only one nvim pls!

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
- Read and edit files through the Nvim buffer (while also writing to disk)
  - We talked about changing this to writing to disk by default, and then telling nvim to reload. That may however cause issues with fresh buffers that have no file yet. Let us know what you think!

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
