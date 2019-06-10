local json_encode = require("cjson.safe").encode
local tostring = tostring
local type = type
local pairs = pairs


local _M = {
    version = 0.1,
    decode = require("cjson.safe").decode,
}


local function serialise_obj(data)
    if type(data) == "function" or type(data) == "userdata"
       or type(data) == "table" then
        return tostring(data)
    end

    return data
end


local function tab_clone_with_serialise(data)
    if type(data) ~= "table" then
        return data
    end

    local t = {}
    for k, v in pairs(data) do
        if type(v) == "table" then
            t[serialise_obj(k)] = tab_clone_with_serialise(v)

        else
            t[serialise_obj(k)] = serialise_obj(v)
        end
    end

    return t
end


local function encode(data, force)
    if force then
        data = tab_clone_with_serialise(data)
    end

    return json_encode(data)
end
_M.encode = encode


local delay_tab = setmetatable({data = "", force = false}, {
    __tostring = function(self)
        return encode(self.data, self.force)
    end
})


-- this is a non-thread safe implementation
-- it works well with log, eg: log.info(..., json.delay_encode({...}))
function _M.delay_encode(data, force)
    delay_tab.data = data
    delay_tab.force = force
    return delay_tab
end


return _M
