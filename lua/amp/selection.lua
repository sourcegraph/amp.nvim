---@brief Selection tracking for Amp Neovim plugin
---@module 'amp.selection'
local M = {}

local logger = require("amp.logger")

-- State management
M.state = {
  latest_selection = nil,
  tracking_enabled = false,
  debounce_timer = nil,
  debounce_ms = 10, -- 10ms is a good tradeoff between performance and not feeling laggy. 100ms already introduced a noticeable delay.
}

---Enable selection tracking
---@param server table The server object to use for broadcasting
function M.enable(server)
  if M.state.tracking_enabled then
    return
  end

  M.state.tracking_enabled = true
  M.server = server

  M._create_autocommands()
  logger.debug("selection", "Selection tracking enabled")
end

---Disable selection tracking
function M.disable()
  if not M.state.tracking_enabled then
    return
  end

  M.state.tracking_enabled = false
  M._clear_autocommands()

  M.state.latest_selection = nil
  M.server = nil

  if M.state.debounce_timer then
    M.state.debounce_timer:stop()
    M.state.debounce_timer:close()
    M.state.debounce_timer = nil
  end

  logger.debug("selection", "Selection tracking disabled")
end

---Convert internal selection format to IDE protocol format
---@param internal_selection table Selection in internal format
---@return table Selection in IDE protocol format
function M.to_ide_format(internal_selection)
  return {
    uri = internal_selection.fileUrl,
    selections = {
      {
        range = {
          startLine = internal_selection.selection.start.line,
          startCharacter = internal_selection.selection.start.character,
          endLine = internal_selection.selection["end"].line,
          endCharacter = internal_selection.selection["end"].character,
        },
        content = internal_selection.text,
      }
    }
  }
end

---Get current cursor position as selection
---@return table|nil Selection object or nil if no valid file
function M.get_cursor_position()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local current_buf = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(current_buf)

  if file_path == "" or not file_path then
    return nil
  end

  -- Get the line content at cursor position
  local line_content = ""
  local success, line = pcall(vim.api.nvim_buf_get_lines, current_buf, cursor_pos[1] - 1, cursor_pos[1], false)
  if success and line and line[1] then
    line_content = line[1]
  end

  return {
    text = "",
    fileUrl = "file://" .. file_path,
    selection = {
      start = { line = cursor_pos[1] - 1, character = cursor_pos[2] },
      ["end"] = { line = cursor_pos[1] - 1, character = cursor_pos[2] },
    },
    lineContent = line_content,
  }
end

---Get current visual selection
---@return table|nil Selection object or nil if not in visual mode
function M.get_visual_selection()
  local current_mode = vim.api.nvim_get_mode().mode

  -- Check if we're in visual mode
  if not (current_mode == "v" or current_mode == "V" or current_mode == "\022") then
    return nil
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(current_buf)

  if file_path == "" or not file_path then
    return nil
  end

  -- Get visual selection marks
  local start_pos = vim.fn.getpos("v")
  local end_pos = vim.fn.getpos(".")

  if start_pos[2] == 0 or end_pos[2] == 0 then
    return nil
  end

  -- Convert to 0-indexed positions
  local start_line = start_pos[2] - 1
  local start_char = start_pos[3] - 1
  local end_line = end_pos[2] - 1
  local end_char = end_pos[3] - 1

  -- Ensure start comes before end
  if start_line > end_line or (start_line == end_line and start_char > end_char) then
    start_line, end_line = end_line, start_line
    start_char, end_char = end_char, start_char
  end

  -- Get selected text
  local lines = vim.api.nvim_buf_get_lines(current_buf, start_line, end_line + 1, false)
  local selected_text = ""

  if #lines > 0 then
    if current_mode == "V" then
      -- Line-wise selection
      selected_text = table.concat(lines, "\n")
    elseif #lines == 1 then
      -- Single line selection
      selected_text = string.sub(lines[1], start_char + 1, end_char + 1)
    else
      -- Multi-line selection
      local text_parts = {}
      table.insert(text_parts, string.sub(lines[1], start_char + 1))
      for i = 2, #lines - 1 do
        table.insert(text_parts, lines[i])
      end
      table.insert(text_parts, string.sub(lines[#lines], 1, end_char + 1))
      selected_text = table.concat(text_parts, "\n")
    end
  end

  return {
    text = selected_text,
    fileUrl = "file://" .. file_path,
    selection = {
      start = { line = start_line, character = start_char },
      ["end"] = { line = end_line, character = end_char },
    }
  }
end

---Get current selection (visual or cursor)
---@return table|nil Current selection object
function M.get_current_selection()
  local visual_sel = M.get_visual_selection()
  if visual_sel then
    return visual_sel
  end

  return M.get_cursor_position()
end

---Check if selection has changed
---@param new_selection table|nil New selection to compare
---@return boolean True if selection changed
function M.has_selection_changed(new_selection)
  local old_selection = M.state.latest_selection

  if not new_selection then
    return old_selection ~= nil
  end

  if not old_selection then
    return true
  end

  if old_selection.fileUrl ~= new_selection.fileUrl then
    return true
  end

  if old_selection.text ~= new_selection.text then
    return true
  end

  local old_sel = old_selection.selection
  local new_sel = new_selection.selection

  if old_sel.start.line ~= new_sel.start.line or
     old_sel.start.character ~= new_sel.start.character or
     old_sel["end"].line ~= new_sel["end"].line or
     old_sel["end"].character ~= new_sel["end"].character then
    return true
  end

  return false
end

---Update and broadcast current selection
function M.update_and_broadcast()
  if not M.state.tracking_enabled or not M.server then
    return
  end

  local current_selection = M.get_current_selection()
  if not current_selection then
    return
  end

  if M.has_selection_changed(current_selection) then
    M.state.latest_selection = current_selection

    local ide_notification = M.to_ide_format(current_selection)
    M.server.broadcast_ide({ selectionDidChange = ide_notification })

    logger.debug("selection", "Selection changed:", ide_notification.uri,
      "lines", ide_notification.selections[1].range.startLine + 1, "-",
      ide_notification.selections[1].range.endLine + 1)
  end
end

---Debounced update function
function M.debounced_update()
  if M.state.debounce_timer then
    M.state.debounce_timer:stop()
    M.state.debounce_timer:close()
  end

  M.state.debounce_timer = vim.defer_fn(function()
    M.update_and_broadcast()
    M.state.debounce_timer = nil
  end, M.state.debounce_ms)
end

---Create autocommands for selection tracking
function M._create_autocommands()
  local group = vim.api.nvim_create_augroup("AmpSelection", { clear = true })

  vim.api.nvim_create_autocmd(
    { "CursorMoved", "CursorMovedI" },
    {
      group = group,
      callback = function()
        M.debounced_update()
      end,
    }
  )

  vim.api.nvim_create_autocmd(
    "ModeChanged",
    {
      group = group,
      callback = function()
        -- Immediate update on mode changes (entering/exiting visual mode)
        M.update_and_broadcast()
      end,
    }
  )
end

---Clear autocommands
function M._clear_autocommands()
  vim.api.nvim_clear_autocmds({ group = "AmpSelection" })
end

return M
