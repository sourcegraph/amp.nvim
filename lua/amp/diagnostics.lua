---@brief Diagnostics sharing for Amp Neovim plugin
---@module 'amp.diagnostics'
local M = {}

---@alias DiagnosticSeverity "error" | "warning" | "info" | "hint"
---@param severity vim.diagnostic.Severity
---@return DiagnosticSeverity
function M._vim_severity_to_protocol(severity)
	if severity == vim.diagnostic.severity.ERROR then
		return "error"
	elseif severity == vim.diagnostic.severity.WARN then
		return "warning"
	elseif severity == vim.diagnostic.severity.INFO then
		return "info"
	elseif severity == vim.diagnostic.severity.HINT then
		return "hint"
	end
	return "info" -- fallback
end

---@class Range
---@field startLine number
---@field startCharacter number
---@field endLine number
---@field endCharacter number

---@class ProtocolDiagnostic
---@field range Range
---@field severity DiagnosticSeverity
---@field description string
---@field lineContent string
---@field startOffset number
---@field endOffset number

---@param diagnostic vim.Diagnostic
---@return ProtocolDiagnostic
function M._vim_diagnostic_to_protocol(diagnostic)
	local line_content = ""
	local ok, lines = pcall(vim.api.nvim_buf_get_lines, diagnostic.bufnr, diagnostic.lnum, diagnostic.lnum + 1, false)
	if ok and lines and lines[1] then
		line_content = lines[1]
	end

	return {
		range = {
			startLine = diagnostic.lnum,
			startCharacter = diagnostic.col,
			endLine = diagnostic.end_lnum,
			endCharacter = diagnostic.end_col,
		},
		severity = M._vim_severity_to_protocol(diagnostic.severity),
		description = diagnostic.message,
		lineContent = line_content,
		startOffset = diagnostic.col,
		endOffset = diagnostic.end_col,
	}
end

---Get diagnostics for a file path (must be open in a buffer)
---@param file_path string Absolute path to file
---@return table|nil entry Diagnostic entry or nil if no buffer found
local function get_diagnostics_for_file(file_path)
	local abs_path = vim.fn.fnamemodify(file_path, ":p")
	local uri = "file://" .. abs_path
	local bufnr = vim.fn.bufnr("^" .. abs_path .. "$")

	if bufnr == -1 then
		return nil
	end

	local diagnostics = {}
	local raw_diagnostics = vim.diagnostic.get(bufnr)
	for _, diag in ipairs(raw_diagnostics) do
		table.insert(diagnostics, M._vim_diagnostic_to_protocol(diag))
	end

	return {
		uri = uri,
		diagnostics = diagnostics,
	}
end

---Get all file paths matching the given path (file or directory)
---@param path string Absolute path to file or directory
---@return string[] List of absolute file paths
local function get_file_paths(path)
	local uv = vim.loop
	local stat = uv.fs_stat(path)

	if not stat then
		return {}
	end

	if stat.type == "file" then
		return { vim.fn.fnamemodify(path, ":p") }
	elseif stat.type == "directory" then
		local abs_dir = vim.fn.fnamemodify(path, ":p")
		if not abs_dir:match("/$") then
			abs_dir = abs_dir .. "/"
		end

		-- Performance: Only collect diagnostics from already-loaded buffers.
		-- We avoid filesystem recursion and don't open new buffers, making this fast.
		-- Trade-off: Unopened files won't have diagnostics, but LSP diagnostics require
		-- buffers to be loaded anyway.
		local file_paths = {}
		for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(bufnr) then
				local ok, buf_name = pcall(vim.api.nvim_buf_get_name, bufnr)
				if ok and buf_name and buf_name ~= "" then
					local abs_buf_name = vim.fn.fnamemodify(buf_name, ":p")
					if abs_buf_name:sub(1, #abs_dir) == abs_dir then
						table.insert(file_paths, abs_buf_name)
					end
				end
			end
		end
		return file_paths
	end

	return {}
end

---Get diagnostics for a specific path (file or directory)
---@param path string Absolute path to file or directory
---@return table entries Array of diagnostic entries
function M.get_diagnostics(path)
	local entries = {}
	local file_paths = get_file_paths(path)

	for _, file_path in ipairs(file_paths) do
		local entry = get_diagnostics_for_file(file_path)
		if entry then
			table.insert(entries, entry)
		end
	end

	return entries
end

return M
