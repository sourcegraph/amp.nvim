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

---Get diagnostics by path prefix (matches single file or all files in directory)
---@param path string Absolute path to file or directory
---@return table entries Array of diagnostic entries
function M.get_diagnostics(path)
	local abs_path = vim.fn.fnamemodify(path, ":p")
	local all_diagnostics = vim.diagnostic.get(nil)
	local entries_by_uri = {}

	for _, diag in ipairs(all_diagnostics) do
		local ok, buf_name = pcall(vim.api.nvim_buf_get_name, diag.bufnr)
		if ok and buf_name and buf_name ~= "" then
			local abs_buf_name = vim.fn.fnamemodify(buf_name, ":p")

			-- Check if buffer path starts with the requested path (prefix match)
			if abs_buf_name:sub(1, #abs_path) == abs_path then
				local uri = "file://" .. abs_buf_name
				if not entries_by_uri[uri] then
					entries_by_uri[uri] = {
						uri = uri,
						diagnostics = {},
					}
				end
				table.insert(entries_by_uri[uri].diagnostics, M._vim_diagnostic_to_protocol(diag))
			end
		end
	end

	local entries = {}
	for _, entry in pairs(entries_by_uri) do
		table.insert(entries, entry)
	end

	return entries
end

return M