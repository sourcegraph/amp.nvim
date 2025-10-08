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

---Get diagnostics for a specific path (file or directory)
---@param path string Absolute path to file or directory
---@return table entries Array of diagnostic entries
function M.get_diagnostics(path)
	local uv = vim.loop
	local stat = uv.fs_stat(path)

	if not stat then
		return {}
	end

	local entries = {}

	if stat.type == "file" then
		-- Single file request - get diagnostics for this specific buffer
		local abs_path = vim.fn.fnamemodify(path, ":p")
		local uri = "file://" .. abs_path
		local bufnr = vim.fn.bufnr("^" .. abs_path .. "$")

		local diagnostics = {}
		if bufnr ~= -1 then
			local raw_diagnostics = vim.diagnostic.get(bufnr)
			for _, diag in ipairs(raw_diagnostics) do
				table.insert(diagnostics, M._vim_diagnostic_to_protocol(diag))
			end
		end

		table.insert(entries, {
			uri = uri,
			diagnostics = diagnostics,
		})
	elseif stat.type == "directory" then
		-- Directory request - get diagnostics for all buffers in this directory
		local abs_dir = vim.fn.fnamemodify(path, ":p")
		-- Ensure directory path ends with /
		if not abs_dir:match("/$") then
			abs_dir = abs_dir .. "/"
		end

		-- Get diagnostics from all buffers
		local all_diagnostics = vim.diagnostic.get(nil)
		local diagnostics_by_uri = {}

		for _, diag in ipairs(all_diagnostics) do
			local ok, buf_name = pcall(vim.api.nvim_buf_get_name, diag.bufnr)
			if ok and buf_name and buf_name ~= "" then
				local abs_buf_name = vim.fn.fnamemodify(buf_name, ":p")
				-- Check if this file is in the requested directory
				-- Must match directory prefix and have a path separator after (or be exact match)
				if abs_buf_name:sub(1, #abs_dir) == abs_dir then
					local uri = "file://" .. abs_buf_name
					if not diagnostics_by_uri[uri] then
						diagnostics_by_uri[uri] = {}
					end
					table.insert(diagnostics_by_uri[uri], M._vim_diagnostic_to_protocol(diag))
				end
			end
		end

		for uri, diag_list in pairs(diagnostics_by_uri) do
			table.insert(entries, {
				uri = uri,
				diagnostics = diag_list,
			})
		end
	end

	return entries
end

return M
