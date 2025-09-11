# Amp Neovim Plugin

Very experimental code for a neovim plugin. Only for internal testing!

Once installed, run `amp --jetbrains` without any other JetBrains IDEs running, only one nvim pls!

Install the plugin by adding this code to your lazy.vim config:

```lua
  -- Amp Plugin
  {
    dir = "/<path-to-the-amp.nvim-repo>",
    name = "amp",
    lazy = false,
    opts = { auto_start = true, log_level = "info" },
  },
```

## Features

- Notify Amp about currently open file (you need to select a file, there's currently no initial sync)
- Notify Amp about selected code
- Read and edit files through the Nvim buffer (while also writing to disk)
  - We talked about changing this to writing to disk by default, and then telling nvim to reload. That may however cause issues with fresh buffers that have no file yet. Let us know what you think!

## Feature Ideas

- When I ask Amp to show me a particular section of code, it would be nice if Amp could open that file and select the code for me.
- Should we keep the code selection when moving between tab? Currently you can't switch to a split terminal if you don't want to loose the selection, i.e. making the built in terminal unfeasible for code selection.

## Running on Linux

The directory for lockfiles is currently hard-coded to a mac variant. Let us know if you run into problems on Linux with that.

```lua
  local home = vim.fn.expand("~")
  local lock_dir = home .. "/.local/share/amp/ide"
  local lockfile_path = lock_dir .. "/" .. tostring(port) .. ".json"
```
