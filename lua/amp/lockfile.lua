local M = {}

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
	-- Properly expand home directory
	local home = vim.fn.expand("~")
	local lock_dir = home .. "/.local/share/amp/ide"
	local lockfile_path = lock_dir .. "/" .. tostring(port) .. ".json"

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

	-- Properly expand home directory
	local home = vim.fn.expand("~")
	local lockfile_path = home .. "/.local/share/amp/ide/" .. tostring(port) .. ".json"
	local success = os.remove(lockfile_path)

	return success ~= nil, success and "Lock file removed" or "Could not remove lock file"
end

return M
