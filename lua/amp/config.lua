local M = {}

M.defaults = {
	port_range = { min = 10000, max = 65535 },
	auto_start = true,
	log_level = "info",
	thread_storage_dir = "/tmp",
	thread_response_timeout = 300000,
	shortcuts = {},
	submit_key = "<C-g>",
	sync_metadata_key = "<C-s>",
	dangerously_allow_all = false,
}

function M.validate(config)
	assert(
		type(config.port_range) == "table"
			and type(config.port_range.min) == "number"
			and type(config.port_range.max) == "number"
			and config.port_range.min > 0
			and config.port_range.max <= 65535
			and config.port_range.min <= config.port_range.max,
		"Invalid port range"
	)

	assert(type(config.auto_start) == "boolean", "auto_start must be a boolean")

	local valid_log_levels = { "trace", "debug", "info", "warn", "error" }
	local is_valid = false
	for _, level in ipairs(valid_log_levels) do
		if config.log_level == level then
			is_valid = true
			break
		end
	end
	assert(is_valid, "log_level must be one of: " .. table.concat(valid_log_levels, ", "))

	assert(type(config.thread_storage_dir) == "string", "thread_storage_dir must be a string")

	assert(
		type(config.thread_response_timeout) == "number" and config.thread_response_timeout > 0,
		"thread_response_timeout must be a positive number (in milliseconds)"
	)

	assert(type(config.shortcuts) == "table", "shortcuts must be a table")

	assert(type(config.dangerously_allow_all) == "boolean", "dangerously_allow_all must be a boolean")

	return true
end

function M.apply(user_config)
	local config = vim.deepcopy(M.defaults)

	if user_config then
		if vim.tbl_deep_extend then
			config = vim.tbl_deep_extend("force", config, user_config)
		else
			for k, v in pairs(user_config) do
				config[k] = v
			end
		end
	end

	config.thread_storage_dir = vim.fn.expand(config.thread_storage_dir)

	if config.shortcuts and type(config.shortcuts) == "table" then
		local normalized_shortcuts = {}
		for i, shortcut in ipairs(config.shortcuts) do
			if type(shortcut) == "table" and shortcut.name then
				normalized_shortcuts[shortcut.name] = shortcut
			end
		end
		for k, v in pairs(config.shortcuts) do
			if type(k) == "string" then
				normalized_shortcuts[k] = v
			end
		end
		config.shortcuts = normalized_shortcuts
	end

	M.validate(config)
	return config
end

return M
