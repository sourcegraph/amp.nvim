---@brief Shortcuts management for Amp
---@module 'amp.shortcuts'
local M = {}
local logger = require("amp.logger")

M.state = {
	shortcuts = {},
}

function M.setup(shortcuts_config)
	M.state.shortcuts = shortcuts_config or {}
	logger.debug("shortcuts", "Loaded " .. vim.tbl_count(M.state.shortcuts) .. " shortcuts")
end

function M.get_all()
	return M.state.shortcuts
end

function M.get(name)
	return M.state.shortcuts[name]
end

function M.expand_shortcuts(text)
	if not text or text == "" then
		return text
	end

	local expanded = text
	local replacements_made = 0

	for name, content in pairs(M.state.shortcuts) do
		local pattern = "#" .. vim.pesc(name)
		local replacement
		if type(content) == "table" then
			replacement = content.prompt or content.details or content.description or ""
		else
			replacement = content
		end
		local count
		expanded, count = expanded:gsub(pattern, replacement)
		replacements_made = replacements_made + count
	end

	if replacements_made > 0 then
		logger.debug("shortcuts", "Expanded " .. replacements_made .. " shortcuts")
	end

	return expanded
end

function M.get_matching_shortcuts(prefix)
	local matches = {}
	
	for name, content in pairs(M.state.shortcuts) do
		if name:find("^" .. vim.pesc(prefix)) then
			table.insert(matches, {
				name = name,
				content = content,
			})
		end
	end

	table.sort(matches, function(a, b)
		return a.name < b.name
	end)

	return matches
end

return M
