---@brief Diagnostics sharing for Amp Neovim plugin
---@module 'amp.diagnostics'
local M = {}

local logger = require("amp.logger")

M.state = {
	diagnostics_enabled = false,
	latest_diagnostics = {},
}

---Enable diagnostics tracking
---@param server table The server object to use for broadcasting
function M.enable(server)
	if M.state.diagnostics_enabled then
		return
	end

	M.state.diagnostics_enabled = true
	M.server = server

	M._create_autocommands()
	logger.debug("diagnostics", "Diagnostics tracking enabled")
end

function M.disable()
	if not M.state.diagnostics_enabled then
		return
	end

	M.state.diagnostics_enabled = false
	M._clear_autocommands()

	M.state.latest_diagnostics = {}
	M.server = nil

	logger.debug("diagnostics", "Diagnostics tracking disabled")
end

---Check if diagnostics has changed
---@param new_diagnostics vim.Diagnostic
---@return boolean
function M.have_diagnostics_changed(new_diagnostics)
	return vim.inspect(M.state.latest_diagnostics) ~= vim.inspect(new_diagnostics)
end

---@alias JetBrainsSeverity "ERROR" | "WARNING" | "WEAK_WARNING" | "INFO"

---@param severity vim.diagnostic.Severity
---@return JetBrainsSeverity
function M._vim_severity_to_jetbrains(severity)
	if severity == vim.diagnostic.severity.ERROR then
		return "ERROR"
	elseif severity == vim.diagnostic.severity.WARN then
		return "WARNING"
	elseif severity == vim.diagnostic.severity.INFO then
		return "INFO"
	elseif severity == vim.diagnostic.severity.HINT then
		-- The JetBrains protocol doesn't recognize "HINT", so we
		-- use "WEAK_WARNING" instead
		return "WEAK_WARNING"
	end

	error("unknown severity level: " .. severity)
end

---@class Range
---@field startLine number
---@field startCharacter number
---@field endLine number
---@field endCharacter number

---@class JetBrainsDiagnostic
---@field range Range
---@field severity JetBrainsSeverity
---@field description string
---@field lineContent string
---@field startOffset number
---@field endOffset number

---@param diagnostic vim.Diagnostic
---@return JetBrainsDiagnostic
function M._vim_diagnostic_to_jetbrains(diagnostic)
	return {
		range = {
			startLine = diagnostic.lnum,
			startCharacter = diagnostic.col,
			endLine = diagnostic.end_lnum,
			endCharacter = diagnostic.end_col,
		},
		severity = M._vim_severity_to_jetbrains(diagnostic.severity),
		description = diagnostic.message,
		lineContent = vim.api.nvim_buf_get_lines(diagnostic.bufnr, diagnostic.lnum, diagnostic.lnum + 1, false)[1],
		startOffset = diagnostic.col,
		endOffset = diagnostic.end_col,
	}
end

function M.broadcast_diagnostics()
	if not M.state.diagnostics_enabled or not M.server then
		return
	end

	local diagnostics = vim.diagnostic.get(nil)

	if M.have_diagnostics_changed(diagnostics) then
		M.state.latest_diagnostics = diagnostics
		local diagnostics_by_bufnr = {}
		for _, value in ipairs(diagnostics) do
			if not diagnostics_by_bufnr[value.bufnr] then
				diagnostics_by_bufnr[value.bufnr] = {}
			end
			table.insert(diagnostics_by_bufnr[value.bufnr], M._vim_diagnostic_to_jetbrains(value))
		end

		for idiagnostic, diagnostic in pairs(diagnostics_by_bufnr) do
			local name = "file://" .. vim.api.nvim_buf_get_name(idiagnostic)
			local diagnostics_message = {
				diagnosticsDidChange = {
					uri = name,
					diagnostics = diagnostic,
				},
			}
			M.server.broadcast_ide(diagnostics_message)
		end
	end
end

---Create autocommands for diagnostics tracking
function M._create_autocommands()
	local group = vim.api.nvim_create_augroup("AmpDiagnostics", { clear = true })

	vim.api.nvim_create_autocmd("DiagnosticChanged", {
		group = group,
		callback = function(_)
			vim.defer_fn(function()
				M.broadcast_diagnostics()
			end, 10)
		end,
	})
end

---Clear autocommands
function M._clear_autocommands()
	vim.api.nvim_clear_autocmds({ group = "AmpDiagnostics" })
end

return M
