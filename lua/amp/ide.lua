---@brief IDE protocol helpers for Amp Neovim plugin
---@module 'amp.ide'
local M = {}

---Wrap a notification in IDE protocol format
---@param notification table The notification data
---@return table Wrapped notification
function M.wrap_notification(notification)
	return { serverNotification = notification }
end

---Wrap a response in IDE protocol format
---@param id string|number The request ID
---@param response table The response data
---@return table Wrapped response
function M.wrap_response(id, response)
	return { serverResponse = vim.tbl_extend("keep", { id = id }, response) }
end

---Wrap an error in IDE protocol format
---@param id string|number The request ID
---@param error table The error data with code and message
---@return table Wrapped error response
function M.wrap_error(id, error)
	return {
		serverResponse = {
			id = id,
			error = error,
		},
	}
end

return M