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
      local parts = vim.split(line, "  ", { plain = false, trimempty = true })
      if #parts >= 5 then
        local thread = {
          title = vim.trim(parts[1]),
          last_updated = vim.trim(parts[2]),
          visibility = vim.trim(parts[3]),
          messages = vim.trim(parts[4]),
          id = vim.trim(parts[5]),
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

  if #threads == 0 then
    vim.notify("No threads found", vim.log.levels.INFO)
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
      prompt_title = "Amp Threads",
      finder = finders.new_table({
        results = threads,
        entry_maker = function(entry)
          return {
            value = entry,
            display = string.format(
              "%-50s  %10s  %8s  %s",
              entry.title:sub(1, 50),
              entry.last_updated,
              entry.messages .. " msgs",
              entry.visibility
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
            "Visibility: " .. entry.value.visibility,
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
            M.continue_thread(thread_id)
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

return M
