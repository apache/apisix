local core = require("apisix.core")
local ngx = require("ngx")
local process = require("ngx.process")

local pairs = pairs
local ipairs = ipairs
local type = type
local timer = ngx.timer
local require = require
local package = package

local plugin_name = "table-count"

local schema = {}
local stop = false
-- only one run of init() function should be running at a time.
-- when init() is reloaded the run number is incremented. It also helps in debugging.
local current_run = 0

local _M = {
  version = 0.1,
  priority = 22902,
  name = plugin_name,
  schema = schema,
  scope = "global",
}

local function tab_item_count(tab, cache,depth)
  if depth == 0 then
    core.log.warn("out of depth..skipping count")
    return
  end
  depth = depth - 1
  cache = cache or {}
  local count = 0
  for _, value in pairs(tab) do
    if cache[value] then
      core.log.warn("circular reference detected..skipping count")
      goto continue
    end
    if type(value) == "table" and not cache[value] then
      cache[value] = true
      local tab_count = tab_item_count(value, cache,depth)
      if tab_count then
        count = count + tab_count + 1
      end
    else
      count = count + 1
    end
    ::continue::
  end
  return count
end

function _M.init()
  package.loaded["apisix.plugins.toolset.config"] = nil
  local config = require("apisix.plugins.toolset.config").table_count
  if config.lua_modules == nil or #config.lua_modules == 0 then
    core.log.warn("no lua_modules provided for table count")
    return
  end
  if not config.scopes then
    core.log.warn("no scope provided. Running for all scopes")
    goto continue
  end
  if #config.scopes ~= 0 then
    for _,scope in ipairs(config.scopes) do
      if process.type() == scope then
        goto continue
      end
    end
    return
  end
  ::continue::
  -- Extract configuration values
  current_run = current_run + 1
  local interval = config.interval or 5
  local run_count
  run_count = function(run_no)
    local depth = config.depth or 1
    for _, package_name in ipairs(config.lua_modules) do
      local package = require(package_name)
      local count = tab_item_count(package, {},depth)
      core.log.warn("package ", package_name, " table count is: ", count," for loaded: ",run_no)
    end
    if stop or run_no ~= current_run then
      return
    end
    local ok, err = timer.at(interval, run_count,current_run)
    if not ok then
      core.log.error("failed to create timer for running table count ", err)
    end
  end

  local ok, err = timer.at(0, run_count,current_run)
  if not ok then
    core.log.error("failed to create timer for running table count ", err)
  end
end

function _M.destroy()
  stop = true
end

return _M
