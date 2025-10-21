local M = {}

local log_levels = {
	trace = 1,
	debug = 2,
	info = 3,
	warn = 4,
	error = 5,
}

local current_level = log_levels.info
local last_error = nil
local log_file = nil

function M.setup(config)
	current_level = log_levels[config.log_level] or 3
	if not log_file then
		local log_path = vim.fn.stdpath("cache") .. "/amp.log"
		log_file = io.open(log_path, "w+")
		if log_file then
			log_file:setvbuf("line")
		end
	end
end

local function log(level, context, ...)
	if log_levels[level] >= current_level then
		local message = table.concat({ ... }, " ")
		local timestamp = os.date("%Y-%m-%d %H:%M:%S")
		local log_line = string.format("[%s] [%s] %s: %s\n", timestamp, level:upper(), context, message)
		
		if log_file then
			log_file:write(log_line)
			log_file:flush()
		end
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
