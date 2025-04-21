local setmetatable = setmetatable
local type         = type
local core         = require("apisix.core")

local _M = {}
local mt = { __index = _M }


function _M.new()
    return setmetatable({}, mt)
end


function _M.send(self, message, event_type)
    local data = type(message) == "table" and core.json.encode(message) or message
    local ok, err = ngx.print("event: " .. (event_type or "message") .. "\ndata: " .. data .. "\n\n")
    if not ok then
        return ok, "failed to write buffer: " .. err
    end
    return ngx.flush(true)
end


return _M
