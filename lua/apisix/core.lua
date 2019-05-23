local tostring = tostring
local json_encode = require("cjson.safe").encode


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


return {
    version = 0.1,
    log = require("apisix.core.log"),
    config = require("apisix.core.config_etcd"),
    json = {
        encode = function(data, force)
            if force then
                data = tab_clone_with_serialise(data)
            end

            return json_encode(data)
        end,
        decode = require("cjson.safe").decode,
    },
    table = {
        new   = require("table.new"),
        clear = require("table.clear"),
        nkeys = require("table.nkeys"),
    },
    response = require("apisix.core.response"),
    typeof = require("apisix.core.typeof"),
    lrucache = require("apisix.core.lrucache"),
    ctx = require("apisix.core.ctx"),
    schema = require("apisix.core.schema"),
}
