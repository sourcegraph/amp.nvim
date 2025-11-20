---@brief Chat buffer interface for Amp
---@module 'amp.chat'
local M = {}
local logger = require("amp.logger")

M.state = {
	buffers = {},
}

local function get_chat_file_path(thread_id)
	if not thread_id then
		return nil
	end
	
	local amp = require("amp")
	local storage_dir = amp.state.config.thread_storage_dir
	vim.fn.mkdir(storage_dir, "p")
	
	return storage_dir .. "/" .. thread_id .. ".md"
end

local function normalize_path(path)
	if not path then
		return nil
	end
	local home = vim.fn.expand("~")
	if path:sub(1, #home) == home then
		return "~" .. path:sub(#home + 1)
	end
	return path
end

local save_timers = {}

local function save_buffer_to_file(buf, thread_id, immediate)
	if not thread_id then
		return
	end
	
	local file_path = get_chat_file_path(thread_id)
	if not file_path then
		return
	end
	
	local function do_save()
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local content = table.concat(lines, "\n")
		
		local file = io.open(file_path, "w")
		if file then
			file:write(content)
			file:close()
			logger.debug("chat", "Saved chat to " .. file_path)
		else
			logger.error("chat", "Failed to save chat to " .. file_path)
		end
	end
	
	if immediate then
		do_save()
	else
		if save_timers[buf] then
			save_timers[buf]:stop()
			save_timers[buf]:close()
		end
		
		save_timers[buf] = vim.loop.new_timer()
		save_timers[buf]:start(500, 0, vim.schedule_wrap(function()
			do_save()
			if save_timers[buf] then
				save_timers[buf]:close()
				save_timers[buf] = nil
			end
		end))
	end
end

local function strip_ansi_codes(str)
	return str:gsub("\27%[[%d;]*m", "")
		:gsub("\27%[%?%d+[hl]", "")
		:gsub("\27%[%d*[ABCDEFGJKST]", "")
		:gsub("\27%]%d+;[^\7]*\7", "")
		:gsub("\27%[[%d;]*[HfABCDEFGJKST]", "")
		:gsub("\27%[=%d+[ul]", "")
		:gsub("\27%[<%d*[ul]", "")
		:gsub("\27%[%?%d+[hl]", "")
		:gsub("\r", "")
end

local function parse_stream_json_line(line)
	if not line or line == "" then
		return nil, nil
	end
	
	local ok, parsed = pcall(vim.json.decode, line)
	if not ok then
		return nil, nil
	end
	
	if not parsed then
		return nil, nil
	end

	local session_id = parsed.session_id
	
	-- Handle assistant messages
	if parsed.type == "assistant" and parsed.message then
		if parsed.message.content then
			local text_parts = {}
			for _, content_block in ipairs(parsed.message.content) do
				if content_block.type == "text" and content_block.text then
					table.insert(text_parts, content_block.text)
				end
			end
			if #text_parts > 0 then
				return table.concat(text_parts, "\n"), session_id
			end
		end
	end
	
	return nil, session_id
end

local function setup_new_thread(buf, new_thread_id)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	logger.info("chat", "Setting up new thread: '" .. new_thread_id .. "'")
	
	M.state.buffers[buf] = M.state.buffers[buf] or {}
	M.state.buffers[buf].thread_id = new_thread_id
	
	local buf_name = "Amp Chat: " .. new_thread_id .. ".md"
	pcall(vim.api.nvim_buf_set_name, buf, buf_name)
	
	local thread_url = "https://ampcode.com/threads/" .. new_thread_id
	logger.info("chat", "Thread URL: " .. thread_url)
	
	local new_file_path = get_chat_file_path(new_thread_id)
	
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	
	local has_filepath = false
	local has_url = false
	local filepath_line_idx = nil
	local url_line_idx = nil
	local cwd_line_idx = nil
	local topic_line_idx = nil
	
	for i, line in ipairs(lines) do
		if line:match("^# filepath:") then
			has_filepath = true
			filepath_line_idx = i - 1
		end
		if line:match("^# thread:") then
			has_url = true
			url_line_idx = i - 1
		end
		if line:match("^# cwd:") then
			cwd_line_idx = i - 1
		end
		if line:match("^# topic:") then
			topic_line_idx = i - 1
		end
	end
	
	-- Add thread URL after topic first (higher in file)
	if not has_url and topic_line_idx then
		vim.api.nvim_buf_set_lines(buf, topic_line_idx + 2, topic_line_idx + 2, false, { "# thread: " .. thread_url })
		-- Update cwd_line_idx since we inserted a line above it
		if cwd_line_idx then
			cwd_line_idx = cwd_line_idx + 1
		end
	elseif has_url and url_line_idx then
		vim.api.nvim_buf_set_lines(buf, url_line_idx, url_line_idx + 1, false, { "# thread: " .. thread_url })
	end
	
	-- Then add filepath after cwd (lower in file)
	if not has_filepath and cwd_line_idx and new_file_path then
		local normalized_path = normalize_path(new_file_path)
		vim.api.nvim_buf_set_lines(buf, cwd_line_idx + 1, cwd_line_idx + 1, false, { "# filepath: " .. normalized_path })
	elseif has_filepath and filepath_line_idx and new_file_path then
		local normalized_path = normalize_path(new_file_path)
		vim.api.nvim_buf_set_lines(buf, filepath_line_idx, filepath_line_idx + 1, false, { "# filepath: " .. normalized_path })
	end
	
	save_buffer_to_file(buf, new_thread_id, true)
end

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

	pcall(vim.api.nvim_buf_set_name, buf, buf_name)
	vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	
	vim.api.nvim_buf_set_var(buf, "lsp_disabled", true)
	vim.api.nvim_buf_set_var(buf, "navigator_disable", true)
	vim.api.nvim_buf_set_var(buf, "amp_chat_buffer", true)
	
	-- Disable LSP and other plugins by setting filetype to a unique value first
	-- This prevents other plugins from attaching during the scheduled callback
	pcall(vim.api.nvim_set_option_value, "filetype", "amp-markdown", { buf = buf })
	
	vim.schedule(function()
		if vim.api.nvim_buf_is_valid(buf) then
			-- Now set to markdown for syntax highlighting
			pcall(vim.api.nvim_set_option_value, "filetype", "markdown", { buf = buf })
		end
	end)

	return buf
end

local function setup_shortcuts_completion(buf)
	vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
		buffer = buf,
		callback = function()
			local line = vim.api.nvim_get_current_line()
			local col = vim.api.nvim_win_get_cursor(0)[2]
			local before_cursor = line:sub(1, col)

			local hash_pos = before_cursor:match(".*()#[%w_-]*$")
			if hash_pos then
				local prefix = before_cursor:sub(hash_pos + 1, col)

				local shortcuts = require("amp.shortcuts")
				local matches = shortcuts.get_matching_shortcuts(prefix)

				if #matches > 0 then
					local items = {}
					for _, match in ipairs(matches) do
						local preview = match.content
						if type(preview) == "table" then
							preview = preview.description or preview.prompt or preview.details or ""
						end
						if #preview > 50 then
							preview = preview:sub(1, 47) .. "..."
						end
						table.insert(items, {
							word = "#" .. match.name,
							abbr = "#" .. match.name,
							menu = preview,
							kind = "Shortcut",
						})
					end

					vim.fn.complete(hash_pos, items)
				end
			end
		end,
	})
end

local function setup_buffer_keymaps(buf, thread_id)
	local opts = { buffer = buf, silent = true, noremap = true }
	
	local amp = require("amp")
	local submit_key = amp.state.config.submit_key or "<C-g>"
	local sync_metadata_key = amp.state.config.sync_metadata_key or "<C-s>"

	vim.keymap.set("n", submit_key, function()
		M.send_message(buf, thread_id)
	end, vim.tbl_extend("force", opts, { desc = "Send message to Amp" }))

	vim.keymap.set("i", submit_key, function()
		M.send_message(buf, thread_id)
	end, vim.tbl_extend("force", opts, { desc = "Send message to Amp" }))
	
	vim.keymap.set("n", sync_metadata_key, function()
		sync_metadata(buf, thread_id)
	end, vim.tbl_extend("force", opts, { desc = "Sync thread metadata" }))
	
	vim.keymap.set("i", sync_metadata_key, function()
		sync_metadata(buf, thread_id)
	end, vim.tbl_extend("force", opts, { desc = "Sync thread metadata" }))

	vim.keymap.set("n", "q", function()
		M.close_chat_buffer(buf)
	end, vim.tbl_extend("force", opts, { desc = "Close chat buffer" }))

	vim.keymap.set("n", "i", function()
		M.enter_input_mode(buf)
	end, vim.tbl_extend("force", opts, { desc = "Enter input mode" }))
	
	vim.keymap.set("n", "<C-a>", function()
		M.toggle_auto_scroll(buf)
	end, vim.tbl_extend("force", opts, { desc = "Toggle auto-scroll" }))
end

local function get_user_input_range(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local separator_line = nil

	-- Find the last separator
	for i = #lines, 1, -1 do
		if lines[i]:match("^🗨:") then
			separator_line = i
			break
		end
	end

	if separator_line then
		-- Look for the next agent marker or separator to define the end
		local end_line = #lines
		for i = separator_line + 1, #lines do
			if lines[i]:match("^🦜:%[amp%]") or lines[i]:match("^🗨:") then
				end_line = i - 1
				break
			end
		end
		return separator_line, end_line
	end

	return nil, nil
end

local function get_working_dir_from_buffer(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	
	for _, line in ipairs(lines) do
		if line == "---" then
			break
		end
		local cwd_match = line:match("^# cwd: (.+)$")
		if cwd_match then
			local expanded = vim.fn.expand(cwd_match)
			local abs = vim.fn.fnamemodify(expanded, ":p")
			return abs
		end
	end
	
	return nil
end

local function get_visibility_from_buffer(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, 15, false)
	
	for _, line in ipairs(lines) do
		local visibility_match = line:match("^# visibility:%s*(%S+)")
		if visibility_match then
			return visibility_match:lower()
		end
	end
	
	return "private"
end

local function get_topic_from_buffer(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, 10, false)
	
	for _, line in ipairs(lines) do
		local topic_match = line:match("^# topic: (.+)$")
		if topic_match and topic_match ~= "New Chat" then
			return topic_match
		end
	end
	
	return nil
end



local function get_cache_path(working_dir)
	local hash = vim.fn.sha256(working_dir)
	return "/tmp/amp_agents_cache_" .. hash .. ".txt"
end

local function read_agents_cache(working_dir)
	local cache_path = get_cache_path(working_dir)
	local file = io.open(cache_path, "r")
	if not file then
		return nil
	end
	
	local content = file:read("*all")
	file:close()
	
	if content == "" then
		return {}
	end
	
	local agents_files = {}
	for line in content:gmatch("[^\n]+") do
		table.insert(agents_files, line)
	end
	return agents_files
end

local function write_agents_cache(working_dir, agents_files)
	local cache_path = get_cache_path(working_dir)
	local file = io.open(cache_path, "w")
	if not file then
		logger.warn("chat", "Failed to write agents cache to " .. cache_path)
		return
	end
	
	file:write(table.concat(agents_files, "\n"))
	file:close()
	logger.debug("chat", "Wrote agents cache to " .. cache_path)
end

local function find_agents_files(working_dir)
	if not working_dir or vim.fn.isdirectory(working_dir) == 0 then
		return {}
	end
	
	-- Try to read from cache first
	local cached = read_agents_cache(working_dir)
	if cached then
		logger.debug("chat", "Using cached agents files for " .. working_dir)
		return cached
	end
	
	local agents_files = {}
	local find_cmd = string.format(
		"find %s -type f \\( -name 'AGENTS.md' -o -name 'AGENT.md' -o -name 'agents.md' -o -name 'agent.md' \\) 2>/dev/null",
		vim.fn.shellescape(working_dir)
	)
	
	local output = vim.fn.system(find_cmd)
	if vim.v.shell_error == 0 and output ~= "" then
		for line in output:gmatch("[^\n]+") do
			local relative = vim.fn.fnamemodify(line, ":." .. working_dir)
			if relative:sub(1, 1) ~= "/" then
				relative = "./" .. relative
			end
			table.insert(agents_files, relative)
		end
	end
	
	-- Write to cache
	write_agents_cache(working_dir, agents_files)
	
	return agents_files
end

local function clear_agents_cache(working_dir)
	local cache_path = get_cache_path(working_dir)
	os.remove(cache_path)
	logger.debug("chat", "Cleared agents cache for " .. working_dir)
end

local function get_agents_files_metadata(working_dir)
	local files = find_agents_files(working_dir)
	local metadata_lines = {}
	
	if #files > 0 then
		for _, file in ipairs(files) do
			table.insert(metadata_lines, "# Agents File: " .. file)
		end
	end
	
	return metadata_lines
end

local function get_thread_stats(thread_id)
	if not thread_id then
		return nil
	end
	
	-- Get thread info from list command
	local list_output = vim.fn.system({ "amp", "threads", "list" })
	if vim.v.shell_error ~= 0 then
		return nil
	end
	
	-- Parse the table output to find our thread
	local lines = vim.split(list_output, "\n", { plain = true })
	for i = 3, #lines do
		if lines[i]:match(thread_id) then
			-- Extract message count from the line
			-- Format: Title  Last Updated  Visibility  Messages  Thread ID
			local message_count = lines[i]:match("(%d+)%s+T%-")
			if message_count then
				return {
					messages = tonumber(message_count),
				}
			end
		end
	end
	
	return nil
end

local function sync_metadata(buf, thread_id)
	if not thread_id then
		thread_id = M.state.buffers[buf] and M.state.buffers[buf].thread_id
	end
	
	if not thread_id then
		vim.notify("⚠️  No thread ID found, cannot sync metadata", vim.log.levels.WARN)
		return
	end
	
	local visibility = get_visibility_from_buffer(buf)
	logger.info("chat", "Syncing metadata - visibility: " .. visibility)
	
	local share_cmd = { "amp", "threads", "share", thread_id, "--visibility", visibility }
	vim.fn.system(share_cmd)
	if vim.v.shell_error == 0 then
		logger.info("chat", "Thread visibility set to " .. visibility)
		vim.notify("✅ Metadata synced (visibility: " .. visibility .. ")", vim.log.levels.INFO)
		if M.state.buffers[buf] then
			M.state.buffers[buf].last_visibility = visibility
		end
	else
		logger.error("chat", "Failed to set thread visibility")
		vim.notify("❌ Failed to sync metadata", vim.log.levels.ERROR)
	end
	
	local topic = get_topic_from_buffer(buf)
	if topic then
		logger.info("chat", "Setting thread name to: " .. topic)
		local rename_cmd = { "amp", "threads", "rename", thread_id, topic }
		vim.fn.system(rename_cmd)
		if vim.v.shell_error == 0 then
			logger.info("chat", "Thread name updated")
		else
			logger.error("chat", "Failed to rename thread")
		end
	end
	
	-- Update thread stats
	logger.info("chat", "Updating thread statistics")
	local stats = get_thread_stats(thread_id)
	if stats then
		local lines_local = vim.api.nvim_buf_get_lines(buf, 0, 20, false)
		local stats_line_idx = nil
		
		for i, line in ipairs(lines_local) do
			if line:match("^# stats:") then
				stats_line_idx = i - 1
				break
			end
		end
		
		local stats_text = "# stats: " .. stats.messages .. " messages"
		
		if stats_line_idx then
			vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
			vim.api.nvim_buf_set_lines(buf, stats_line_idx, stats_line_idx + 1, false, { stats_text })
			logger.info("chat", "Updated stats line")
		else
			-- Add stats after visibility
			for i, line in ipairs(lines_local) do
				if line:match("^# visibility:") then
					vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
					vim.api.nvim_buf_set_lines(buf, i, i, false, { stats_text })
					logger.info("chat", "Added stats line after visibility")
					break
				end
			end
		end
	end
	
	-- Refresh agents files list
	logger.info("chat", "Refreshing agents files list")
	local working_dir = get_working_dir_from_buffer(buf) or vim.fn.getcwd()
	clear_agents_cache(working_dir)  -- Clear cache to force re-scan
	local agents_lines = get_agents_files_metadata(working_dir)
	
	-- Find and replace the agents files section
	lines = vim.api.nvim_buf_get_lines(buf, 0, 50, false)
	local agents_start = nil
	local agents_end = nil
	
	for i, line in ipairs(lines) do
		if line:match("^# Agents File:") then
			agents_start = i - 1
			for j = i, #lines do
				if lines[j]:match("^# Agents File:") then
					agents_end = j - 1
				else
					break
				end
			end
			break
		end
	end
	
	if agents_start then
		vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
		vim.api.nvim_buf_set_lines(buf, agents_start, agents_end + 1, false, agents_lines)
		logger.info("chat", "Agents files list refreshed")
	elseif #agents_lines > 0 then
		-- Insert agents files after visibility section
		for i, line in ipairs(lines) do
			if line:match("^# visibility:") then
				vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
				for idx, agent_line in ipairs(agents_lines) do
					vim.api.nvim_buf_set_lines(buf, i + idx - 1, i + idx - 1, false, { agent_line })
				end
				logger.info("chat", "Agents files list added")
				break
			end
		end
	end
	
	save_buffer_to_file(buf, thread_id, true)
end

function M.sync_metadata_command()
	local buf = vim.api.nvim_get_current_buf()
	
	if not vim.api.nvim_buf_get_var(buf, "amp_chat_buffer") then
		vim.notify("⚠️  This is not an Amp chat buffer", vim.log.levels.WARN)
		return
	end
	
	local thread_id = M.state.buffers[buf] and M.state.buffers[buf].thread_id
	
	if not thread_id then
		local lines = vim.api.nvim_buf_get_lines(buf, 0, 20, false)
		for _, line in ipairs(lines) do
			local id = line:match("^# thread: https://ampcode%.com/threads/(T%-[a-f0-9%-]+)")
			if id then
				thread_id = id
				break
			end
		end
	end
	
	sync_metadata(buf, thread_id)
end

local function ensure_output_window()
	local amp = require("amp")
	if not amp.state.config.use_output_window then
		return nil, nil
	end

	-- Check if window is valid
	if M.state.output_win and vim.api.nvim_win_is_valid(M.state.output_win) then
		return M.state.output_win, M.state.output_buf
	end

	-- Check if buffer exists but window is closed
	if M.state.output_buf and vim.api.nvim_buf_is_valid(M.state.output_buf) then
		-- Open split with existing buffer
		vim.cmd("botright 15split")
		M.state.output_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(M.state.output_win, M.state.output_buf)
	else
		-- Create new buffer and window
		vim.cmd("botright 15split")
		M.state.output_win = vim.api.nvim_get_current_win()
		M.state.output_buf = vim.api.nvim_create_buf(false, true) -- scratch buffer
		
		-- Try to name it, but ignore error if name exists
		pcall(vim.api.nvim_buf_set_name, M.state.output_buf, "Amp Output")
		
		vim.api.nvim_set_option_value("filetype", "markdown", { buf = M.state.output_buf })
		vim.api.nvim_set_option_value("buftype", "nofile", { buf = M.state.output_buf })
		vim.api.nvim_set_option_value("bufhidden", "hide", { buf = M.state.output_buf })
		vim.api.nvim_set_option_value("swapfile", false, { buf = M.state.output_buf })
		vim.api.nvim_win_set_buf(M.state.output_win, M.state.output_buf)
	end
	
	-- Set window options
	vim.api.nvim_set_option_value("wrap", true, { win = M.state.output_win })
	
	-- Return focus to previous window
	vim.cmd("wincmd p")
	
	return M.state.output_win, M.state.output_buf
end

local function append_to_output_window(lines)
	local win, buf = ensure_output_window()
	if not win or not buf then return end
	
	local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
	
	-- Scroll to bottom
	if vim.api.nvim_win_is_valid(win) then
		local new_count = vim.api.nvim_buf_line_count(buf)
		vim.api.nvim_win_set_cursor(win, { new_count, 0 })
		-- Force redraw to show update
		vim.cmd("redraw")
	end
end

function M.send_message(buf, passed_thread_id)
	if M.state.buffers[buf] and M.state.buffers[buf].sending then
		-- Queue the message instead of rejecting it
		local start_line, end_line = get_user_input_range(buf)
		if start_line then
			local message_lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line, false)
			local message = table.concat(message_lines, "\n"):gsub("^%s*(.-)%s*$", "%1")
			
			if message and message ~= "" then
				local shortcuts = require("amp.shortcuts")
				message = shortcuts.expand_shortcuts(message)
				
				M.state.buffers[buf].queued_messages = M.state.buffers[buf].queued_messages or {}
				table.insert(M.state.buffers[buf].queued_messages, message)
				
				-- Clear the input area
				vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
				vim.api.nvim_buf_set_lines(buf, start_line - 1, end_line, false, { "🗨:", "" })
				
				vim.notify("📋 Message queued (" .. #M.state.buffers[buf].queued_messages .. " in queue)", vim.log.levels.INFO)
			else
				vim.notify("⚠️  Message already in progress, please wait...", vim.log.levels.WARN)
			end
		end
		return
	end

	local thread_id = passed_thread_id or (M.state.buffers[buf] and M.state.buffers[buf].thread_id)
	
	-- Try to extract thread_id from buffer content if not found in state
	if not thread_id then
		local lines = vim.api.nvim_buf_get_lines(buf, 0, 20, false)
		for _, line in ipairs(lines) do
			local id = line:match("^# thread: https://ampcode%.com/threads/(T%-[a-f0-9%-]+)")
			if id then
				thread_id = id
				logger.info("chat", "Extracted thread ID from buffer: " .. thread_id)
				break
			end
		end
	end
	
	logger.info("chat", "send_message called with thread_id: " .. (thread_id or "nil"))
	
	-- Always re-read working_dir from buffer to respect user changes
	local working_dir = get_working_dir_from_buffer(buf) or vim.fn.getcwd()
	
	-- Update state with the current working directory
	M.state.buffers[buf] = M.state.buffers[buf] or {}
	M.state.buffers[buf].working_dir = working_dir
	
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

	local shortcuts = require("amp.shortcuts")
	message = shortcuts.expand_shortcuts(message)
	
	-- Validate working directory exists
	if vim.fn.isdirectory(working_dir) == 0 then
		vim.notify("❌ Working directory does not exist: " .. working_dir, vim.log.levels.ERROR)
		logger.error("chat", "Invalid working directory: " .. working_dir)
		return
	end

	M.state.buffers[buf].sending = true
	
	-- Sync metadata immediately if we have a thread_id
	if thread_id then
		sync_metadata(buf, thread_id)
	end
	
	save_buffer_to_file(buf, thread_id, true)

	vim.notify("⏳ Sending message to Amp...", vim.log.levels.INFO)

	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	
	-- Add a new input separator immediately so the user can queue the next message
	vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "🗨:", "" })
	
	-- Add agent response area below the queue input
	vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "🦜:[amp]", "" })
	
	-- Store the position of the agent response
	local agent_response_line = vim.api.nvim_buf_line_count(buf)

	local spinner_timer = start_spinner(buf)
	
	-- Initialize auto-scroll state (default: enabled to follow agent output)
	M.state.buffers[buf].auto_scroll = M.state.buffers[buf].auto_scroll == nil and true or M.state.buffers[buf].auto_scroll
	
	-- Scroll to show the agent response area
	local win = vim.fn.bufwinid(buf)
	if win ~= -1 then
		vim.api.nvim_win_set_cursor(win, { agent_response_line, 0 })
	end
	
	-- Add status line after the agent marker
	vim.api.nvim_buf_set_lines(buf, agent_response_line, agent_response_line, false, { "⏳ Starting..." })

	local amp = require("amp")
	local thread_storage_dir = amp.state.config.thread_storage_dir

	local cmd
	local job_opts = {
		cwd = working_dir,
		-- Disable PTY to prevent output buffering and enable true streaming
		pty = false,
	}
	
	if thread_id then
		cmd = { "amp", "threads", "continue", thread_id }
		if amp.state.config.use_stream_json then
			table.insert(cmd, "--stream-json")
		end
		if amp.state.config.dangerously_allow_all then
			table.insert(cmd, "--dangerously-allow-all")
		end
		table.insert(cmd, "--execute")
		table.insert(cmd, message)
	else
		cmd = { "amp" }
		if amp.state.config.use_stream_json then
			table.insert(cmd, "--stream-json")
		end
		if amp.state.config.dangerously_allow_all then
			table.insert(cmd, "--dangerously-allow-all")
		end
		table.insert(cmd, "--execute")
		table.insert(cmd, message)
		job_opts.env = { AMP_THREAD_STORAGE_DIR = thread_storage_dir }
	end

	-- Wrap the command to pipe raw stdout to a log file for debugging
	local escaped_args = {}
	for _, arg in ipairs(cmd) do
		table.insert(escaped_args, vim.fn.shellescape(arg))
	end
	local shell_cmd = table.concat(escaped_args, " ") .. " | tee -a amp_raw.log"
	cmd = { "sh", "-c", shell_cmd }

	local response_lines = {}
	local timeout_timer = nil
	local stdin_written = false
	local job_id = nil

	logger.info("chat", "Starting job with command: " .. vim.inspect(cmd))
	logger.info("chat", "Full command string: " .. table.concat(cmd, " "))
	
	local function has_meaningful_data(data)
		if not data then return false end
		for _, s in ipairs(data) do
			if s and s ~= "" then return true end
		end
		return false
	end

	local function on_timeout()
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
			end
			if timeout_timer then
				timeout_timer:close()
				timeout_timer = nil
			end
		end)
	end

	local function reset_timeout()
		if timeout_timer and not vim.loop.is_closing(timeout_timer) then
			timeout_timer:stop()
			timeout_timer:start(amp.state.config.thread_response_timeout, 0, on_timeout)
		end
	end
	
	job_opts.on_stdout = function(_, data)
		if not data then
			return
		end

		if has_meaningful_data(data) then
			reset_timeout()
		end

		vim.schedule(function()
			if not vim.api.nvim_buf_is_valid(buf) then
				return
			end

			vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

			local cleaned_data = {}
			for _, line in ipairs(data) do
				if amp.state.config.use_stream_json then
					logger.debug("chat", "stdout raw line: " .. line)
					local text, session_id = parse_stream_json_line(line)
					
					if session_id and not thread_id then
						thread_id = session_id
						setup_new_thread(buf, thread_id)
					end
					
					if text then
						text = text:gsub("\\n", "\n")
						logger.debug("chat", "stdout parsed text: " .. text)
						-- Split multi-line text into separate lines for buffer insertion
						local text_lines = vim.split(text, "\n", { plain = true })
						for _, text_line in ipairs(text_lines) do
							table.insert(cleaned_data, text_line)
							table.insert(response_lines, text_line)
						end
					end
				else
					local cleaned_line = strip_ansi_codes(line)
					table.insert(cleaned_data, cleaned_line)
					table.insert(response_lines, cleaned_line)
				end
			end

			if #cleaned_data > 0 then
				append_to_output_window(cleaned_data)
				
				-- Append to the end of the buffer (below the queue input)
				vim.api.nvim_buf_set_lines(buf, -1, -1, false, cleaned_data)

				local win = vim.fn.bufwinid(buf)
				if win ~= -1 and M.state.buffers[buf] and M.state.buffers[buf].auto_scroll then
					-- Auto-scroll to show streaming content if enabled
					local new_line_count = vim.api.nvim_buf_line_count(buf)
					vim.api.nvim_win_set_cursor(win, { new_line_count, 0 })
					vim.cmd("redraw")
				end
				
				local id_for_save = thread_id or (M.state.buffers[buf] and M.state.buffers[buf].thread_id)
				if id_for_save then
					save_buffer_to_file(buf, id_for_save)
				end
			end
		end)
	end
	
	job_opts.on_stderr = function(_, data)
		if not data then
			return
		end

		if has_meaningful_data(data) then
			reset_timeout()
		end

		vim.schedule(function()
			if not vim.api.nvim_buf_is_valid(buf) then
				return
			end

			vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

			local cleaned_data = {}
			for _, line in ipairs(data) do
				if amp.state.config.use_stream_json then
					logger.debug("chat", "stderr raw line: " .. line)
					local text, session_id = parse_stream_json_line(line)
					
					if session_id and not thread_id then
						thread_id = session_id
						setup_new_thread(buf, thread_id)
					end
					
					if text then
						text = text:gsub("\\n", "\n")
						logger.debug("chat", "stderr parsed text: " .. text)
						-- Split multi-line text into separate lines for buffer insertion
						local text_lines = vim.split(text, "\n", { plain = true })
						for _, text_line in ipairs(text_lines) do
							table.insert(cleaned_data, text_line)
							table.insert(response_lines, text_line)
							if text_line ~= "" then
								logger.debug("chat", "Amp CLI JSON text line: " .. text_line)
							end
						end
					else
						local cleaned_line = strip_ansi_codes(line)
						if cleaned_line ~= "" then
							logger.debug("chat", "Amp CLI stderr (non-JSON): " .. cleaned_line)
						end
					end
				else
					local cleaned_line = strip_ansi_codes(line)
					table.insert(cleaned_data, cleaned_line)
					table.insert(response_lines, cleaned_line)
					
					if cleaned_line ~= "" then
						logger.debug("chat", "Amp CLI stderr: " .. cleaned_line)
					end
				end
			end

			if #cleaned_data > 0 then
				append_to_output_window(cleaned_data)
				
				-- Append to the end of the buffer (below the queue input)
				vim.api.nvim_buf_set_lines(buf, -1, -1, false, cleaned_data)

				local win = vim.fn.bufwinid(buf)
				if win ~= -1 and M.state.buffers[buf] and M.state.buffers[buf].auto_scroll then
					-- Auto-scroll to show streaming content if enabled
					local new_line_count = vim.api.nvim_buf_line_count(buf)
					vim.api.nvim_win_set_cursor(win, { new_line_count, 0 })
					vim.cmd("redraw")
				end
				
				local id_for_save = thread_id or (M.state.buffers[buf] and M.state.buffers[buf].thread_id)
				if id_for_save then
					save_buffer_to_file(buf, id_for_save)
				end
			end
		end)
	end
	
	job_opts.on_exit = function(_, exit_code)
		logger.info("chat", "Job exited with code: " .. exit_code)
		stop_spinner(buf, spinner_timer)

		if timeout_timer then
			timeout_timer:stop()
			timeout_timer:close()
			timeout_timer = nil
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
						-- Get the most recent thread from the list
						local list_output = vim.fn.system({ "amp", "threads", "list" })
						logger.info("chat", "amp threads list output: " .. list_output)
						
						-- The output is a table, get the first thread ID from the second line (skip header)
						local lines = vim.split(list_output, "\n", { plain = true })
						local new_thread_id = nil
						for i = 3, #lines do -- Skip header and separator line
							new_thread_id = lines[i]:match("(T%-[a-f0-9%-]+)")
							if new_thread_id then
								break
							end
						end
						
						if new_thread_id then
							logger.info("chat", "Extracted thread ID from amp threads list: '" .. new_thread_id .. "'")
							setup_new_thread(buf, new_thread_id)
							thread_id = new_thread_id
						else
							logger.warn("chat", "Could not extract thread ID from list output")
						end
					end

					local current_thread_id = thread_id or (M.state.buffers[buf] and M.state.buffers[buf].thread_id)
					
					-- Always save buffer immediately on exit to ensure all output is captured
					if current_thread_id then
						save_buffer_to_file(buf, current_thread_id, true)
						-- Don't sync metadata here since we already did it before sending
					end

					-- Handle queue input cleanup and setup for next message
					local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
					local last_agent_line = nil
					for i = #lines, 1, -1 do
						if lines[i]:match("^🦜:%[amp%]") then
							last_agent_line = i
							break
						end
					end

					local draft_content = nil
					if last_agent_line then
						-- Search backwards for the queue input
						for i = last_agent_line - 1, 1, -1 do
							if lines[i]:match("^🗨:") then
								-- Found the queue input
								local content_lines = vim.api.nvim_buf_get_lines(buf, i, last_agent_line - 1, false)
								if #content_lines > 0 then
									local text = table.concat(content_lines, "\n")
									if text:match("%S") then
										draft_content = text
									end
								end
								
								-- Remove the queue input block
								vim.api.nvim_buf_set_lines(buf, i - 1, last_agent_line - 1, false, {})
								break
							end
						end
					end

					-- Add new input block at the bottom
					vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "🗨:", "" })

					-- Check for queued messages
					local has_queued = M.state.buffers[buf] 
						and M.state.buffers[buf].queued_messages 
						and #M.state.buffers[buf].queued_messages > 0
					
					if has_queued then
						local queued_message = table.remove(M.state.buffers[buf].queued_messages, 1)
						local remaining = #M.state.buffers[buf].queued_messages
						
						-- Put into bottom block
						vim.api.nvim_buf_set_lines(buf, -1, -1, false, vim.split(queued_message, "\n"))
						
						vim.notify("✅ Message sent. Processing queued message (" .. remaining .. " remaining)...", vim.log.levels.INFO)
						
						-- Auto-send the queued message after a brief delay
						vim.defer_fn(function()
							if vim.api.nvim_buf_is_valid(buf) then
								M.send_message(buf, current_thread_id)
							end
						end, 100)
					elseif draft_content then
						-- Restore draft content
						vim.api.nvim_buf_set_lines(buf, -1, -1, false, vim.split(draft_content, "\n"))
						vim.notify("✅ Message sent. Draft restored.", vim.log.levels.INFO)
					else
						vim.notify("✅ Message sent successfully", vim.log.levels.INFO)
					end
				else
					vim.notify("❌ Failed to send message (exit code: " .. exit_code .. ")", vim.log.levels.ERROR)
				end
			end)
	end
	
	job_opts.stdout_buffered = false
	job_opts.stderr_buffered = false
	job_opts.stdin = "null"
	
	job_id = vim.fn.jobstart(cmd, job_opts)
	
	if job_id <= 0 then
		stop_spinner(buf, spinner_timer)
		logger.error("chat", "Failed to start job, job_id: " .. job_id)
		vim.notify("❌ Failed to start amp command", vim.log.levels.ERROR)
		if M.state.buffers[buf] then
			M.state.buffers[buf].sending = false
		end
		return
	end

	M.state.buffers[buf] = M.state.buffers[buf] or {}
	M.state.buffers[buf].job_id = job_id

	timeout_timer = vim.loop.new_timer()
	timeout_timer:start(amp.state.config.thread_response_timeout, 0, on_timeout)
end

function M.enter_input_mode(buf)
	local lines = vim.api.nvim_buf_line_count(buf)
	vim.api.nvim_win_set_cursor(0, { lines, 0 })
	vim.cmd("startinsert!")
end

function M.open_chat_buffer(thread_id, initial_message, topic)
	logger.info("chat", "open_chat_buffer called with thread_id: " .. (thread_id or "nil"))
	
	local buf = create_chat_buffer(thread_id, nil)
	local working_dir = get_working_dir_from_buffer(buf) or vim.fn.getcwd()

	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	local file_path = get_chat_file_path(thread_id)
	local loaded_from_file = false
	
	if file_path and vim.fn.filereadable(file_path) == 1 then
		local file = io.open(file_path, "r")
		if file then
			local content = file:read("*all")
			file:close()
			
			local lines = vim.split(content, "\n", { plain = true })
			
			local has_filepath = false
			local has_agents = false
			local cwd_line_idx = nil
			local visibility_line_idx = nil
			for i, line in ipairs(lines) do
				if line:match("^# filepath:") then
					has_filepath = true
				end
				if line:match("^# cwd:") then
					cwd_line_idx = i
				end
				if line:match("^# visibility:") then
					visibility_line_idx = i
				end
				if line:match("^# Agents File:") then
					has_agents = true
				end
			end
			
			if not has_filepath and cwd_line_idx then
				table.insert(lines, cwd_line_idx + 1, "# filepath: " .. file_path)
				if visibility_line_idx then
					visibility_line_idx = visibility_line_idx + 1
				end
			end
			
			if not has_agents and visibility_line_idx then
				local agents_lines = get_agents_files_metadata(working_dir)
				for j = #agents_lines, 1, -1 do
					table.insert(lines, visibility_line_idx + 1, agents_lines[j])
				end
			end
			
			-- Add stats if not present
			local has_stats = false
			for _, line in ipairs(lines) do
				if line:match("^# stats:") then
					has_stats = true
					break
				end
			end
			
			if not has_stats and thread_id and visibility_line_idx then
				local stats = get_thread_stats(thread_id)
				if stats then
					table.insert(lines, visibility_line_idx + 1, "# stats: " .. stats.messages .. " messages")
				end
			end
			
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			loaded_from_file = true
			logger.info("chat", "Loaded chat from " .. file_path)
			
			local last_line = lines[#lines] or ""
			if not last_line:match("^🗨:") then
				vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "🗨:", "" })
			end
			
			save_buffer_to_file(buf, thread_id, true)
		end
	end
	
	if not loaded_from_file then
		-- If thread_id exists but no file, try to fetch from server
		if thread_id and not initial_message then
			logger.info("chat", "Fetching thread history from server for " .. thread_id)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Loading thread history..." })
			
			local output = vim.fn.system({ "amp", "threads", "show", thread_id })
			if vim.v.shell_error == 0 and output ~= "" then
				local lines = vim.split(output, "\n", { plain = true })
				-- Add metadata at the top
				local metadata = {
					"# topic: Thread " .. thread_id,
					"",
					"# thread: https://ampcode.com/threads/" .. thread_id,
					"# cwd: " .. normalize_path(working_dir),
					"# filepath: " .. normalize_path(file_path),
					"# visibility: private # (public, unlisted, workspace, group)",
				}
				
				-- Add agents files metadata
				local agents_lines = get_agents_files_metadata(working_dir)
				for _, line in ipairs(agents_lines) do
					table.insert(metadata, line)
				end
				
				table.insert(metadata, "")
				table.insert(metadata, "---")
				table.insert(metadata, "")
				
				-- Combine metadata with fetched content
				for _, line in ipairs(lines) do
					table.insert(metadata, line)
				end
				
				-- Add input prompt at the end
				table.insert(metadata, "")
				table.insert(metadata, "🗨:")
				table.insert(metadata, "")
				
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, metadata)
				save_buffer_to_file(buf, thread_id, true)
				loaded_from_file = true
				logger.info("chat", "Loaded thread history from server")
			else
				logger.warn("chat", "Failed to fetch thread from server: " .. output)
			end
		end
		
		if not loaded_from_file then
			local topic_line = topic or "New Chat"
			
			local initial_lines = {}
			table.insert(initial_lines, "# topic: " .. topic_line)
			table.insert(initial_lines, "")
			if thread_id then
				table.insert(initial_lines, "# thread: https://ampcode.com/threads/" .. thread_id)
			end
			table.insert(initial_lines, "# cwd: " .. normalize_path(working_dir))
			if file_path then
				table.insert(initial_lines, "# filepath: " .. normalize_path(file_path))
			end
			table.insert(initial_lines, "# visibility: private # (public, unlisted, workspace, group)")
			
			-- Add agents files metadata
			local agents_lines = get_agents_files_metadata(working_dir)
			for _, line in ipairs(agents_lines) do
				table.insert(initial_lines, line)
			end
			
			table.insert(initial_lines, "")
			table.insert(initial_lines, "---")
			table.insert(initial_lines, "")
			table.insert(initial_lines, "🗨:")
			table.insert(initial_lines, initial_message or "")

			vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)
		end
	end

	setup_buffer_keymaps(buf, thread_id)
	setup_shortcuts_completion(buf)

	M.state.buffers[buf] = {
		thread_id = thread_id,
		working_dir = working_dir,
		created_at = os.time(),
		last_visibility = get_visibility_from_buffer(buf),
	}
	
	logger.info("chat", "Buffer state set - buf: " .. buf .. ", thread_id: " .. (thread_id or "nil"))

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
	
	if save_timers[buf] then
		save_timers[buf]:stop()
		save_timers[buf]:close()
		save_timers[buf] = nil
	end

	M.state.buffers[buf] = nil

	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end

function M.toggle_auto_scroll(buf)
	if not M.state.buffers[buf] then
		return
	end
	
	M.state.buffers[buf].auto_scroll = not M.state.buffers[buf].auto_scroll
	local status = M.state.buffers[buf].auto_scroll and "enabled" or "disabled"
	vim.notify("Auto-scroll " .. status, vim.log.levels.INFO)
end

return M
