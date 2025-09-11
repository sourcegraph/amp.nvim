local M = {}

M.defaults = {
  port_range = { min = 10000, max = 65535 },
  auto_start = true,
  log_level = "info",
}

function M.validate(config)
  assert(
    type(config.port_range) == "table"
      and type(config.port_range.min) == "number"
      and type(config.port_range.max) == "number"
      and config.port_range.min > 0
      and config.port_range.max <= 65535
      and config.port_range.min <= config.port_range.max,
    "Invalid port range"
  )
  
  assert(type(config.auto_start) == "boolean", "auto_start must be a boolean")
  
  local valid_log_levels = { "trace", "debug", "info", "warn", "error" }
  local is_valid = false
  for _, level in ipairs(valid_log_levels) do
    if config.log_level == level then
      is_valid = true
      break
    end
  end
  assert(is_valid, "log_level must be one of: " .. table.concat(valid_log_levels, ", "))
  
  return true
end

function M.apply(user_config)
  local config = vim.deepcopy(M.defaults)
  
  if user_config then
    if vim.tbl_deep_extend then
      config = vim.tbl_deep_extend("force", config, user_config)
    else
      for k, v in pairs(user_config) do
        config[k] = v
      end
    end
  end
  
  M.validate(config)
  return config
end

return M
