local M = {}



-- Get the user's home directory. The fallback handles edge cases where
-- vim.loop.os_homedir() returns nil (missing HOME/USERPROFILE env vars,
-- broken containers, permission issues), but this is unlikely without
-- bigger system problems.
local function homedir()
	return vim.loop.os_homedir() or vim.fn.expand("~")
end

-- Resolve the base data directory following ../amp repository pattern
local function get_data_home()
	-- Optional override for testing/debugging
	local override = os.getenv("AMP_DATA_HOME")
	if override and override ~= "" then
		return override
	end

	local sys = vim.loop.os_uname().sysname
	local standard_dir = vim.fs.joinpath(homedir(), ".local", "share")
	
	-- Match ../amp/core/src/common/dirs.ts logic:
	-- On Windows/macOS: use standard dir (~/.local/share)
	-- On Linux: use XDG_DATA_HOME if set, otherwise standard dir
	if sys == "Windows_NT" or sys == "Darwin" then
		return standard_dir
	else
		-- Linux/Unix: respect XDG if provided, fallback to standard dir
		local xdg = os.getenv("XDG_DATA_HOME")
		if xdg and xdg ~= "" then
			return xdg
		end
		return standard_dir
	end
end

local function lock_dir_base()
	return vim.fs.joinpath(get_data_home(), "amp", "ide")
end

-- Generate a random authentication token
function M.generate_auth_token()
	local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	local token = {}

	-- Use time and process ID for seeding
	math.randomseed(os.time() + vim.fn.getpid())

	-- Generate 32 character token
	for i = 1, 32 do
		local char_index = math.random(1, #chars)
		table.insert(token, chars:sub(char_index, char_index))
	end

	return table.concat(token)
end

-- Create a lock file with port and auth token
function M.create(port, auth_token)
	local lock_dir = lock_dir_base()
	local lockfile_path = vim.fs.joinpath(lock_dir, tostring(port) .. ".json")

	-- Create directory structure if it doesn't exist
	local mkdir_success = vim.fn.mkdir(lock_dir, "p")
	if mkdir_success == 0 then
		return false, "Could not create lock directory: " .. lock_dir
	end

	-- Create the lock file
	local file = io.open(lockfile_path, "w")
	if not file then
		return false, "Could not create lock file: " .. lockfile_path
	end

	-- Get current working directory and nvim version info
	local cwd = vim.fn.getcwd()
	local version = vim.version()
	local ide_name = string.format("nvim %d.%d.%d", version.major, version.minor, version.patch)

	local lock_data = {
		port = port,
		authToken = auth_token,
		pid = vim.fn.getpid(),
		workspaceFolders = { cwd },
		ideName = ide_name,
	}

	file:write(vim.json.encode(lock_data))
	file:close()

	return true, lockfile_path
end

-- Remove a lock file
function M.remove(port)
	if not port then
		return false, "No port specified"
	end

	local lockfile_path = vim.fs.joinpath(lock_dir_base(), tostring(port) .. ".json")
	local success = os.remove(lockfile_path)

	return success ~= nil, success and "Lock file removed" or "Could not remove lock file"
end

return M
