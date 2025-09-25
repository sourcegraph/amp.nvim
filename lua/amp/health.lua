local M = {}

---Perform health checks for the Amp plugin
function M.check()
	local amp = require("amp")

	vim.health.start("@sourcegraph/amp.nvim")

	-- Check if plugin is initialized
	if amp.state.initialized then
		vim.health.ok("Plugin is initialized")
	else
		vim.health.error("Plugin is not initialized - run require('amp').setup()")
		return
	end

	-- Check server status
	if amp.state.server then
		vim.health.ok("WebSocket server is running on port " .. tostring(amp.state.port))

		-- Check connection status
		if amp.state.connected then
			vim.health.ok("Connected to Amp CLI")
		else
			vim.health.warn("No Amp CLI clients connected")
		end

		-- Check authentication
		if amp.state.auth_token then
			vim.health.ok("Authentication token is configured")
		else
			vim.health.warn("No authentication token (running in insecure mode)")
		end

		-- Check lockfile
		local lockfile_path = vim.fn.expand("~/.local/share/amp/ide/" .. tostring(amp.state.port) .. ".json")
		if vim.fn.filereadable(lockfile_path) == 1 then
			vim.health.ok("Lockfile exists at " .. lockfile_path)
		else
			vim.health.error("Lockfile missing at " .. lockfile_path)
		end
	else
		vim.health.error("WebSocket server is not running", "run :AmpStart")
	end

	-- Check Amp CLI availability
	if vim.fn.executable("amp") == 1 then
		local amp_path = vim.fn.exepath("amp")
		vim.health.ok("Amp CLI found at " .. amp_path)

		-- Try to get version
		local version_output = vim.fn.system("amp --version 2>/dev/null")
		if vim.v.shell_error == 0 and version_output ~= "" then
			local version = version_output:gsub("%s+", "")
			vim.health.ok("Amp CLI version: " .. version)
		else
			vim.health.warn("Could not determine Amp CLI version")
		end
	else
		-- Provide OS-specific installation instructions
		local install_cmd
		if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
			install_cmd = 'powershell -c "irm ampcode.com/install.ps1|iex"'
		else
			install_cmd = "curl -s https://ampcode.com/install.sh | bash"
		end

		vim.health.error("Amp CLI not found in PATH", "Install with: " .. install_cmd)
	end

	-- Check workspace folders
	local workspace_folders = vim.fn.getcwd()
	if workspace_folders and workspace_folders ~= "" then
		vim.health.ok("Workspace folder: " .. workspace_folders)
	else
		vim.health.warn("No workspace folder detected")
	end
end

return M
