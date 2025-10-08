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

---Send a message to append to the prompt field in the IDE
---@param message string The message to append to the prompt
---@return boolean success Whether message was sent successfully
function M.send_to_prompt(message)
	local amp = require("amp")
	if not amp.state.server then
		logger.warn("message", "Server is not running - start it first with :AmpStart")
		return false
	end

	local success = amp.state.server.broadcast_ide({
		appendToPrompt = { message = message },
	})

	if success then
		logger.debug("message", "Message appended to prompt")
	else
		logger.error("message", "Failed to append message to prompt")
	end

	return success
end

return M
