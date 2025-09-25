---@brief Message sending functionality for Amp Neovim plugin
---@module 'amp.message'
local M = {}

local logger = require("amp.logger")

---Send a message to the agent using userSentMessage notification
---@param message string The message to send
---@return boolean success Whether message was sent successfully
function M.send_message(message)
	local amp = require("amp")
	if not amp.state.server then
		logger.warn("message", "Server is not running - start it first with :AmpStart")
		return false
	end

	local success = amp.state.server.broadcast_ide({
		userSentMessage = { message = message },
	})

	if success then
		logger.debug("message", "Message sent to agent")
	else
		logger.error("message", "Failed to send message to agent")
	end

	return success
end

return M
