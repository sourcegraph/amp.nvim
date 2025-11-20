---@brief Telescope integration for Amp thread managementamp.amp.
---@module 'amp.telescope'
local M = {}
local logger = require("amp.logger")

local function is_telescope_available()
  local ok = pcall(require, "telescope")
  return ok
end

local function parse_thread_list(output)
  local threads = {}
  local lines = vim.split(output, "\n", { plain = true })

  for i, line in ipairs(lines) do
    if i > 2 and line ~= "" then
      -- Extract thread ID (last column, format T-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
      local thread_id = line:match("(T%-[a-f0-9%-]+)%s*$")
      
      if thread_id then
        -- Remove the thread ID from the line (escape special chars for gsub)
        local escaped_id = thread_id:gsub("%-", "%%-")
        local remaining = line:gsub(escaped_id .. "%s*$", "")
        
        -- Extract messages (number before thread ID)
        local messages = remaining:match("(%d+)%s*$")
        if messages then
          remaining = remaining:gsub(messages .. "%s*$", "")
        end
        
        -- Extract visibility (Private/Public before messages)
        local visibility = remaining:match("(%w+)%s*$")
        if visibility then
          remaining = remaining:gsub(visibility .. "%s*$", "")
        end
        
        -- Extract last updated (e.g., "15s ago", "2m ago")
        local last_updated = remaining:match("(%d+[smhd]%s+ago)%s*$")
        if last_updated then
          remaining = remaining:gsub(last_updated:gsub("%-", "%%-") .. "%s*$", "")
        end
        
        -- What's left is the title
        local title = vim.trim(remaining)
        
        local thread = {
          title = title,
          last_updated = last_updated or "",
          visibility = visibility or "",
          messages = messages or "",
          id = thread_id,
        }
        table.insert(threads, thread)
      end
    end
  end

  return threads
end

function M.list_threads(opts)
  if not is_telescope_available() then
    logger.error("telescope", "Telescope.nvim is not installed")
    vim.notify("Telescope.nvim is required for this feature", vim.log.levels.ERROR)
    return
  end

  opts = opts or {}

  local output = vim.fn.system({ "amp", "threads", "list" })
  if vim.v.shell_error ~= 0 then
    logger.error("telescope", "Failed to list threads: " .. output)
    vim.notify("Failed to list threads. Make sure you're logged in to Amp.", vim.log.levels.ERROR)
    return
  end

  local threads = parse_thread_list(output)

  table.insert(threads, 1, {
    title = "Create new thread",
    last_updated = "",
    visibility = "",
    messages = "",
    id = "__new__",
  })

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  pickers
    .new(opts, {
      prompt_title = "Amp Threads",
      finder = finders.new_table({
        results = threads,
        entry_maker = function(entry)
          local title_with_time = entry.title
          if entry.last_updated and entry.last_updated ~= "" then
            title_with_time = string.format("%s (%s)", entry.title, entry.last_updated)
          end
          return {
            value = entry,
            display = string.format(
              "%-70s  %s",
              title_with_time:sub(1, 70),
              entry.id
            ),
            ordinal = entry.title .. " " .. entry.id,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_buffer_previewer({
        title = "Thread Details",
        define_preview = function(self, entry)
          local lines = {
            "Title: " .. entry.value.title,
            "ID: " .. entry.value.id,
            "Last Updated: " .. entry.value.last_updated,
            "Messages: " .. entry.value.messages,
            "",
            "Press <CR> to continue thread in chat buffer",
            "Press <C-o> to open thread in browser",
            "Press <C-n> to create a new thread",
          }
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            local thread_id = selection.value.id
            if thread_id == "__new__" then
              M.new_thread()
            else
              M.continue_thread(thread_id)
            end
          end
        end)

        map("i", "<C-o>", function()
          local selection = action_state.get_selected_entry()
          if selection then
            local thread_id = selection.value.id
            local url = "https://ampcode.com/threads/" .. thread_id
            vim.fn.jobstart({ "open", url }, { detach = true })
            vim.notify("Opening thread in browser: " .. url, vim.log.levels.INFO)
          end
        end)

        map("i", "<C-n>", function()
          actions.close(prompt_bufnr)
          M.new_thread()
        end)

        return true
      end,
    })
    :find()
end

function M.continue_thread(thread_id)
  local chat = require("amp.chat")
  chat.open_chat_buffer(thread_id)
end

function M.new_thread(initial_message)
  local chat = require("amp.chat")
  chat.open_chat_buffer(nil, initial_message)
end

function M.list_shortcuts(opts)
  if not is_telescope_available() then
    logger.error("telescope", "Telescope.nvim is not installed")
    vim.notify("Telescope.nvim is required for this feature", vim.log.levels.ERROR)
    return
  end

  opts = opts or {}

  local shortcuts = require("amp.shortcuts")
  local all_shortcuts = shortcuts.get_all()

  local items = {}
  for name, content in pairs(all_shortcuts) do
    local item = {
      name = name,
      shortcut = "#" .. name,
    }
    
    if type(content) == "table" then
      item.description = content.description or ""
      item.details = content.details or content.prompt or ""
      item.prompt = content.prompt or ""
    else
      item.description = content
      item.details = content
      item.prompt = content
    end
    
    table.insert(items, item)
  end

  table.sort(items, function(a, b)
    return a.name < b.name
  end)

  if #items == 0 then
    vim.notify("No shortcuts defined", vim.log.levels.INFO)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  pickers
    .new(opts, {
      prompt_title = "Amp Shortcuts",
      finder = finders.new_table({
        results = items,
        entry_maker = function(entry)
          return {
            value = entry,
            display = string.format("%-30s  %s", entry.shortcut, entry.description),
            ordinal = entry.name .. " " .. entry.description,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_buffer_previewer({
        title = "Shortcut Details",
        define_preview = function(self, entry)
          local lines = {
            "Shortcut: " .. entry.value.shortcut,
            "Name: " .. entry.value.name,
            "",
            "Description:",
            entry.value.description,
            "",
            "Details:",
            entry.value.details,
            "",
            "Press <CR> to insert shortcut at cursor",
          }
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        end,
      }),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            local shortcut = selection.value.shortcut
            vim.api.nvim_put({ shortcut }, "c", true, true)
          end
        end)
        return true
      end,
    })
    :find()
end

return M
