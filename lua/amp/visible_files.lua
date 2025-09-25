---@brief Visible files tracking for Amp Neovim plugin
---@module 'amp.visible_files'
local M = {}

local logger = require("amp.logger")

-- State management
M.state = {
	tracking_enabled = false,
	latest_files = {},
}

---Enable visible files tracking
---@param server table The server object to use for broadcasting
function M.enable(server)
	if M.state.tracking_enabled then
		return
	end

	M.state.tracking_enabled = true
	M.server = server

	M._create_autocommands()
	logger.debug("visible_files", "Visible files tracking enabled")

	-- Send initial visible files
	vim.defer_fn(function()
		M.broadcast_visible_files()
	end, 100)
end

---Disable visible files tracking
function M.disable()
	if not M.state.tracking_enabled then
		return
	end

	M.state.tracking_enabled = false
	M._clear_autocommands()

	M.state.latest_files = {}
	M.server = nil

	logger.debug("visible_files", "Visible files tracking disabled")
end

---Get all currently visible files
---@return table List of file URIs
function M.get_current_visible_files()
	local uris = {}
	local seen = {}

	-- Get all buffers that are displayed in windows
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) then
			local buf = vim.api.nvim_win_get_buf(win)
			if vim.api.nvim_buf_is_valid(buf) then
				local name = vim.api.nvim_buf_get_name(buf)
				if name ~= "" and not seen[name] then
					-- Check if file exists before adding to URIs
					local stat = vim.loop.fs_stat(name)
					if stat then
						seen[name] = true
						table.insert(uris, "file://" .. name)
					end
				end
			end
		end
	end

	return uris
end

---Check if visible files have changed
---@param new_files table List of new file URIs
---@return boolean True if files changed
function M.have_files_changed(new_files)
	local old_files = M.state.latest_files

	if #old_files ~= #new_files then
		return true
	end

	-- Create sets for comparison
	local old_set = {}
	for _, uri in ipairs(old_files) do
		old_set[uri] = true
	end

	for _, uri in ipairs(new_files) do
		if not old_set[uri] then
			return true
		end
	end

	return false
end

---Broadcast visible files if changed
function M.broadcast_visible_files(force)
	if not M.state.tracking_enabled or not M.server then
		return
	end

	local current_files = M.get_current_visible_files()

	if force or M.have_files_changed(current_files) then
		M.state.latest_files = current_files

		M.server.broadcast_ide({
			visibleFilesDidChange = { uris = current_files },
		})

		logger.debug("visible_files", "Visible files changed, count:", #current_files)
		for i, uri in ipairs(current_files) do
			if i <= 3 then -- Log first 3 files
				local filename = uri:match("file://.*/(.*)")
				logger.debug("visible_files", "  " .. i .. ":", filename or uri)
			elseif i == 4 and #current_files > 3 then
				logger.debug("visible_files", "  ... and", #current_files - 3, "more files")
				break
			end
		end
	end
end

---Create autocommands for visible files tracking
function M._create_autocommands()
	local group = vim.api.nvim_create_augroup("AmpVisibleFiles", { clear = true })

	-- Buffer events
	vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWinLeave" }, {
		group = group,
		callback = function(_)
			-- Small delay to let window/buffer state settle
			vim.defer_fn(function()
				M.broadcast_visible_files()
			end, 10)
		end,
	})

	-- Window events
	vim.api.nvim_create_autocmd({ "WinNew", "WinClosed" }, {
		group = group,
		callback = function()
			vim.defer_fn(function()
				M.broadcast_visible_files()
			end, 10)
		end,
	})

	-- Tab events
	vim.api.nvim_create_autocmd({ "TabEnter", "TabClosed", "TabNew" }, {
		group = group,
		callback = function()
			vim.defer_fn(function()
				M.broadcast_visible_files()
			end, 10)
		end,
	})

	-- File events
	vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
		group = group,
		callback = function()
			vim.defer_fn(function()
				M.broadcast_visible_files()
			end, 10)
		end,
	})
end

---Clear autocommands
function M._clear_autocommands()
	vim.api.nvim_clear_autocmds({ group = "AmpVisibleFiles" })
end

return M
