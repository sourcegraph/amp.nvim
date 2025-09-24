---@brief Message sending functionality for Amp Neovim plugin
---@module 'amp.message'
local M = {}

local logger = require("amp.logger")

-- State management
M.state = {
	draft_buffer = nil,
	draft_window = nil,
}

---Send a message to the agent using userSentMessage notification
---@param message string The message to send
---@return boolean success Whether message was sent successfully
function M.send_message(message)
	local amp = require("amp")
	if not amp.state.server then
		logger.warn("message", "Server is not running - start it first with :AmpStart")
		return false
	end

	local success = amp.state.server.broadcast_ide({
		userSentMessage = { message = message },
	})

	if success then
		logger.debug("message", "Message sent to agent")
	else
		logger.error("message", "Failed to send message to agent")
	end

	return success
end

---Open a draft message buffer
---@param split_type string "vertical" or "horizontal"
---@param size number|nil Size of the split (columns for vertical, rows for horizontal)
---@param direction string|nil Direction for split: "right", "left", "top", "bottom" (defaults: "right" for vertical, "bottom" for horizontal)
---@return boolean success Whether draft buffer was opened successfully
function M.open_draft(split_type, size, direction)
	-- Clean up stale state if buffer/window was closed manually
	if M.state.draft_buffer and not vim.api.nvim_buf_is_valid(M.state.draft_buffer) then
		M.state.draft_buffer = nil
		M.state.draft_window = nil
	end
	if M.state.draft_window and not vim.api.nvim_win_is_valid(M.state.draft_window) then
		M.state.draft_window = nil
	end

	local buf
	-- Reuse existing buffer if it exists, otherwise create new one
	if M.state.draft_buffer and vim.api.nvim_buf_is_valid(M.state.draft_buffer) then
		buf = M.state.draft_buffer
	else
		-- Create a new buffer
		buf = vim.api.nvim_create_buf(false, true) -- not listed, scratch buffer
		if not buf then
			logger.error("message", "Failed to create draft buffer")
			return false
		end

		-- Set buffer options
		vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
		vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
		vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
		vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
		vim.api.nvim_buf_set_name(buf, "[Amp Draft Message]")

		-- Set up buffer-local command for sending
		vim.api.nvim_buf_create_user_command(buf, "AmpSendDraft", function()
			M.send_draft()
		end, { desc = "Send draft message to Amp agent" })
	end

	if not buf then
		logger.error("message", "Failed to set draft buffer")
		return false
	end

	-- Create the split window
	local win_cmd = ""
	local size_str = size and tostring(size) or ""

	if split_type == "vertical" then
		local dir = direction or "right"
		if dir == "left" then
			win_cmd = "leftabove " .. size_str .. "vsplit"
		else -- right (default)
			win_cmd = "rightbelow " .. size_str .. "vsplit"
		end
	else -- horizontal
		local dir = direction or "bottom"
		if dir == "top" then
			win_cmd = "leftabove " .. size_str .. "split"
		else -- bottom (default)
			win_cmd = "rightbelow " .. size_str .. "split"
		end
	end

	vim.cmd(win_cmd)
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	-- Store state
	M.state.draft_buffer = buf
	M.state.draft_window = win

	-- Position cursor at the end of the buffer
	local line_count = vim.api.nvim_buf_line_count(buf)
	local last_line = vim.api.nvim_buf_get_lines(buf, line_count - 1, line_count, false)[1] or ""
	local last_col = #last_line
	vim.api.nvim_win_set_cursor(win, { line_count, last_col })

	logger.debug("message", "Draft message buffer opened")
	return true
end

---Send the draft message and close the buffer
---@return boolean success Whether draft was sent successfully
function M.send_draft()
	if not M.state.draft_buffer or not vim.api.nvim_buf_is_valid(M.state.draft_buffer) then
		logger.warn("message", "No valid draft buffer found")
		return false
	end

	-- Get all lines from the buffer
	local lines = vim.api.nvim_buf_get_lines(M.state.draft_buffer, 0, -1, false)

	-- Join lines and trim whitespace
	local message = table.concat(lines, "\n"):gsub("^%s*(.-)%s*$", "%1")

	if message == "" then
		logger.warn("message", "Draft message is empty")
		return false
	end

	-- Send the message
	local success = M.send_message(message)

	if success then
		-- Close the draft buffer
		M.close_draft()
		logger.debug("message", "Draft message sent and buffer closed")
	end

	return success
end

---Close the draft message buffer
function M.close_draft()
	if M.state.draft_window and vim.api.nvim_win_is_valid(M.state.draft_window) then
		vim.api.nvim_win_close(M.state.draft_window, false)
	end

	if M.state.draft_buffer and vim.api.nvim_buf_is_valid(M.state.draft_buffer) then
		vim.api.nvim_buf_delete(M.state.draft_buffer, { force = true })
	end

	M.state.draft_buffer = nil
	M.state.draft_window = nil
end

---Open draft message in vertical split
---@param cols number|nil Number of columns for the split
---@param direction string|nil Direction for split: "right" (default) or "left"
---@return boolean success Whether draft buffer was opened successfully
function M.open_draft_vertical(cols, direction)
	return M.open_draft("vertical", cols, direction)
end

---Open draft message in horizontal split
---@param rows number|nil Number of rows for the split
---@param direction string|nil Direction for split: "bottom" (default) or "top"
---@return boolean success Whether draft buffer was opened successfully
function M.open_draft_horizontal(rows, direction)
	return M.open_draft("horizontal", rows, direction)
end

---Check if current buffer is the draft message buffer
---@return boolean is_draft Whether current buffer is the draft buffer
function M.is_draft_buffer()
	local current_buf = vim.api.nvim_get_current_buf()
	return current_buf == M.state.draft_buffer
end

---Get the draft buffer number (for exclusion from visible files)
---@return number|nil bufnr The draft buffer number or nil if not open
function M.get_draft_buffer()
	if M.state.draft_buffer and vim.api.nvim_buf_is_valid(M.state.draft_buffer) then
		return M.state.draft_buffer
	end
	return nil
end

---Create user commands for message functionality
function M.create_commands()
	-- Command to send a message directly
	vim.api.nvim_create_user_command("Amp", function(opts)
		local message = opts.args
		if message == "" then
			logger.warn("message", "Please provide a message to send")
			return
		end

		-- Save and restore visual selection if it exists
		local start_pos, end_pos, mode
		if opts.range > 0 then
			start_pos = vim.fn.getpos("'<")
			end_pos = vim.fn.getpos("'>")
			mode = vim.fn.visualmode()

			-- Restore visual selection before sending so agent can see it
			vim.fn.setpos(".", start_pos)
			vim.cmd("normal! " .. mode)
			vim.fn.setpos(".", end_pos)
		end

		M.send_message(message)
	end, {
		nargs = "*",
		range = true,
		desc = "Send a message to the Amp agent",
	})

	-- Command to open draft message buffer
	vim.api.nvim_create_user_command("AmpDraft", function()
		M.open_draft("horizontal")
	end, { desc = "Open draft message buffer for Amp agent" })
end

return M
