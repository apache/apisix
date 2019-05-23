local core = require("apisix.core")
local plugin_name = "key-auth"
local consumers


local _M = {
    version = 0.1,
    priority = 2500,
    name = plugin_name,
}


function _M.init(conf)
    if consumers then
        consumers.close()
    end

    consumers = core.config.new("/plugins/key-auth/consumers",
                                {automatic = true})
end


function _M.check_args(conf)
    return true
end


function _M.access(conf, ctx)
    local key = core.request.header(ctx, "apikey")
    if not key then
        return 401, {message = "Invalid API key found in request"}
    end

    -- local limit_ins = core.lrucache.plugin_ctx(plugin_name, ctx,
    --                                            create_limit_obj, conf)
    local consumer_id
    for _, consumer in ipairs(consumers.values) do
        if key == consumer.value.key then
            consumer_id = consumer.value.id
            break
        end
    end

    if not consumer_id then
        return 401, {message = "Invalid API key in request"}
    end

    core.log.warn("passed key-auth access")
end


return _M
