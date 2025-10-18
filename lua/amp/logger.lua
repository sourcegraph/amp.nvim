local M = {}

local log_levels = {
	trace = 1,
	debug = 2,
	info = 3,
	warn = 4,
	error = 5,
}

local current_level = 3 -- info
local last_error = nil

function M.setup(config)
	current_level = log_levels[config.log_level] or 3
end

local function log(level, context, ...)
	if log_levels[level] >= current_level then
		local message = table.concat({ ... }, " ")
		local notify_level = vim.log.levels[level:upper()] or vim.log.levels.INFO
		vim.notify(string.format("%s: %s", context, message), notify_level)
	end
end

function M.trace(context, ...)
	log("trace", context, ...)
end

function M.debug(context, ...)
	log("debug", context, ...)
end

function M.info(context, ...)
	log("info", context, ...)
end

function M.warn(context, ...)
	log("warn", context, ...)
end

function M.error(context, ...)
	local message = table.concat({ ... }, " ")
	last_error = {
		context = context,
		message = message,
		timestamp = os.time(),
	}
	log("error", context, ...)
end

function M.get_last_error()
	return last_error
end

return M
