---@brief Chat buffer interface for Amp
---@module 'amp.chat'
local M = {}
local logger = require("amp.logger")

M.state = {
	buffers = {},
}

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local function start_spinner(buf)
	local frame_idx = 1
	local spinner_line = nil

	local timer = vim.loop.new_timer()
	timer:start(
		0,
		100,
		vim.schedule_wrap(function()
			if not vim.api.nvim_buf_is_valid(buf) then
				timer:stop()
				return
			end

			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			for i = #lines, 1, -1 do
				if lines[i]:match("^🦜:%[amp%]") then
					spinner_line = i - 1
					break
				end
			end

			if spinner_line then
				vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
				vim.api.nvim_buf_set_lines(
					buf,
					spinner_line,
					spinner_line + 1,
					false,
					{ "🦜:[amp] " .. spinner_frames[frame_idx] }
				)
				frame_idx = (frame_idx % #spinner_frames) + 1
			end
		end)
	)

	return timer
end

local function stop_spinner(buf, timer)
	if timer then
		timer:stop()
		timer:close()
	end

	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	vim.schedule(function()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		for i = #lines, 1, -1 do
			if lines[i]:match("^🦜:%[amp%]") then
				vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
				vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { "🦜:[amp]" })
				break
			end
		end
	end)
end

local function create_chat_buffer(thread_id, working_dir)
	local buf = vim.api.nvim_create_buf(false, true)
	local buf_name = thread_id and ("Amp Chat: " .. thread_id .. ".md") or "Amp Chat: New Thread.md"

	vim.api.nvim_buf_set_name(buf, buf_name)
	vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

	return buf
end

local function setup_buffer_keymaps(buf, thread_id)
	local opts = { buffer = buf, silent = true, noremap = true }

	vim.keymap.set("n", "<C-g>", function()
		M.send_message(buf, thread_id)
	end, vim.tbl_extend("force", opts, { desc = "Send message to Amp" }))

	vim.keymap.set("i", "<C-g>", function()
		M.send_message(buf, thread_id)
	end, vim.tbl_extend("force", opts, { desc = "Send message to Amp" }))

	vim.keymap.set("n", "q", function()
		M.close_chat_buffer(buf)
	end, vim.tbl_extend("force", opts, { desc = "Close chat buffer" }))

	vim.keymap.set("n", "i", function()
		M.enter_input_mode(buf)
	end, vim.tbl_extend("force", opts, { desc = "Enter input mode" }))
end

local function get_user_input_range(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local separator_line = nil

	for i = #lines, 1, -1 do
		if lines[i]:match("^🗨:") then
			separator_line = i
			break
		end
	end

	if separator_line then
		return separator_line, #lines
	end

	return nil, nil
end

function M.send_message(buf, passed_thread_id)
	if M.state.buffers[buf] and M.state.buffers[buf].sending then
		vim.notify("⚠️  Message already in progress, please wait...", vim.log.levels.WARN)
		return
	end

	local thread_id = passed_thread_id or (M.state.buffers[buf] and M.state.buffers[buf].thread_id)
	local working_dir = M.state.buffers[buf] and M.state.buffers[buf].working_dir
	
	local start_line, end_line = get_user_input_range(buf)

	if not start_line then
		vim.notify("No user input found. Type your message after the 🗨: separator", vim.log.levels.WARN)
		return
	end

	local message_lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line, false)
	local message = table.concat(message_lines, "\n"):gsub("^%s*(.-)%s*$", "%1")

	if message == "" then
		vim.notify("Message cannot be empty", vim.log.levels.WARN)
		return
	end

	M.state.buffers[buf] = M.state.buffers[buf] or {}
	M.state.buffers[buf].sending = true

	vim.notify("⏳ Sending message to Amp...", vim.log.levels.INFO)

	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "🦜:[amp]", "" })

	local spinner_timer = start_spinner(buf)

	local amp = require("amp")
	local thread_storage_dir = amp.state.config.thread_storage_dir

	local cmd
	if thread_id then
		cmd = string.format(
			"cd %s && echo %s | amp threads continue %s --execute",
			vim.fn.shellescape(working_dir or vim.fn.getcwd()),
			vim.fn.shellescape(message),
			thread_id
		)
	else
		cmd = string.format(
			"cd %s && echo %s | AMP_THREAD_DIR=%s amp --execute",
			vim.fn.shellescape(working_dir or vim.fn.getcwd()),
			vim.fn.shellescape(message),
			vim.fn.shellescape(thread_storage_dir)
		)
	end

	local response_lines = {}
	local timeout_timer = nil

	local job_id = vim.fn.jobstart(cmd, {
		on_stdout = function(_, data)
			if not data then
				return
			end

			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(buf) then
					return
				end

				vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

				for _, line in ipairs(data) do
					table.insert(response_lines, line)
				end

				local current_line_count = vim.api.nvim_buf_line_count(buf)
				vim.api.nvim_buf_set_lines(buf, current_line_count, current_line_count, false, data)

				local win = vim.fn.bufwinid(buf)
				if win ~= -1 then
					local new_line_count = vim.api.nvim_buf_line_count(buf)
					vim.api.nvim_win_set_cursor(win, { new_line_count, 0 })
				end
			end)
		end,
		on_stderr = function(_, data)
			if data and #data > 0 then
				vim.schedule(function()
					for _, line in ipairs(data) do
						if line ~= "" then
							logger.error("chat", "Amp CLI: " .. line)
						end
					end
				end)
			end
		end,
		on_exit = function(_, exit_code)
			stop_spinner(buf, spinner_timer)

			if timeout_timer then
				timeout_timer:stop()
				timeout_timer:close()
			end

			if M.state.buffers[buf] then
				M.state.buffers[buf].sending = false
			end

			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(buf) then
					return
				end

				vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

				if exit_code == 0 then
					if not thread_id then
						local list_output = vim.fn.system({ "amp", "threads", "list" })
						local list_lines = vim.split(list_output, "\n", { plain = true })
						
						if #list_lines > 2 then
							local first_thread_line = list_lines[3]
							local parts = vim.split(first_thread_line, "  ", { plain = false, trimempty = true })
							if #parts >= 5 then
								local new_thread_id = vim.trim(parts[5])
								M.state.buffers[buf].thread_id = new_thread_id
								
								local buf_name = "Amp Chat: " .. new_thread_id .. ".md"
								vim.api.nvim_buf_set_name(buf, buf_name)
								
								logger.info("chat", "Thread created: " .. new_thread_id)
							end
						end
					end

					vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "🗨:", "" })
					vim.notify("✅ Message sent successfully", vim.log.levels.INFO)

					local win = vim.fn.bufwinid(buf)
					if win ~= -1 then
						local total_lines = vim.api.nvim_buf_line_count(buf)
						vim.api.nvim_win_set_cursor(win, { total_lines, 0 })
					end
				else
					vim.notify("❌ Failed to send message (exit code: " .. exit_code .. ")", vim.log.levels.ERROR)
				end
			end)
		end,
		stdout_buffered = false,
		stderr_buffered = false,
		shell = true,
	})

	M.state.buffers[buf] = M.state.buffers[buf] or {}
	M.state.buffers[buf].job_id = job_id

	timeout_timer = vim.loop.new_timer()
	timeout_timer:start(amp.state.config.thread_response_timeout, 0, function()
		vim.schedule(function()
			if M.state.buffers[buf] and M.state.buffers[buf].sending then
				vim.fn.jobstop(job_id)
				stop_spinner(buf, spinner_timer)
				
				if M.state.buffers[buf] then
					M.state.buffers[buf].sending = false
				end
				
				vim.notify(
					"⏱️  Thread response timed out after " 
						.. (amp.state.config.thread_response_timeout / 1000) 
						.. " seconds",
					vim.log.levels.WARN
				)
				
				if vim.api.nvim_buf_is_valid(buf) then
					vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
					vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "🗨:", "" })
				end
			end
			
			if timeout_timer then
				timeout_timer:close()
			end
		end)
	end)
end

function M.enter_input_mode(buf)
	local lines = vim.api.nvim_buf_line_count(buf)
	vim.api.nvim_win_set_cursor(0, { lines, 0 })
	vim.cmd("startinsert!")
end

function M.open_chat_buffer(thread_id, initial_message, topic)
	local working_dir = vim.fn.getcwd()
	local buf = create_chat_buffer(thread_id, working_dir)

	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	local topic_line = topic or "New Chat"
	
	local initial_lines = {
		"# topic: " .. topic_line,
		"# cwd: " .. working_dir,
		"",
		"---",
		"",
		"🗨:",
		initial_message or "",
	}

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)

	setup_buffer_keymaps(buf, thread_id)

	M.state.buffers[buf] = {
		thread_id = thread_id,
		working_dir = working_dir,
		created_at = os.time(),
	}

	if initial_message and initial_message ~= "" then
		vim.notify("Press <C-g> to send the message or edit it first", vim.log.levels.INFO)
	else
		M.enter_input_mode(buf)
	end

	local total_lines = vim.api.nvim_buf_line_count(buf)
	vim.api.nvim_win_set_cursor(win, { total_lines, 0 })
end

function M.close_chat_buffer(buf)
	local state = M.state.buffers[buf]
	if state then
		if state.job_id then
			vim.fn.jobstop(state.job_id)
		end
		if state.spinner_timer then
			state.spinner_timer:stop()
			state.spinner_timer:close()
		end
	end

	M.state.buffers[buf] = nil

	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end

return M
