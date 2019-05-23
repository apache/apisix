local core = require("apisix.core")
local plugin_name = "key-auth"


local _M = {
    version = 0.1,
    priority = 2500,
    name = plugin_name,
}


function _M.init(conf)
end


function _M.check_args(conf)
    return true
end


function _M.access(conf, ctx)
    local key = core.request.header(ctx, "apikey")
    if not key then
        core.response.say(401, {message = "No API key found in request"})
        return
    end

    core.log.warn("apikey: ", key)

    core.log.warn("hit key-auth access")
end


return _M
