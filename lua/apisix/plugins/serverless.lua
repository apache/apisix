local core = require("apisix.core")
local plugin_name = "serverless"


local schema = {
    type = "object",
    properties = {
        rate = {type = "integer", minimum = 0},
        burst = {type = "integer",  minimum = 0},
        key = {type = "string"},
        rejected_code = {type = "integer", minimum = 200},
    },
    required = {"rate", "burst", "key", "rejected_code"}
}


local _M = {
    version = 0.1,
    priority = 1001,        -- TODO: add a type field, may be a good idea
    name = plugin_name,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


function _M.access(conf, ctx)
    local key = ctx.var[conf.key]
    local delay, err = lim:incoming(key, true)
    if not delay then
        if err == "rejected" then
            return conf.rejected_code
        end

        core.log.error("failed to limit req: ", err)
        return 500
    end
end

return _M
