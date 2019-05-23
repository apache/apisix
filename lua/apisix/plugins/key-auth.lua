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


local create_consume_cache
do
    local consumer_ids = {}

    function create_consume_cache()
        core.table.clear(consumer_ids)

        for _, consumer in ipairs(consumers.values) do
            consumer_ids[consumer.value.key] = consumer.value.id
        end

        return consumer_ids
    end

end -- do


function _M.check_args(conf)
    return true
end


function _M.access(conf, ctx)
    local key = core.request.header(ctx, "apikey")
    if not key then
        return 401, {message = "Missing API key found in request"}
    end

    local consumers_hash = core.lrucache.plugin(plugin_name, "consumers_key",
                                consumers.version, create_consume_cache)

    local consumer_id = consumers_hash[key]
    if not consumer_id then
        return 401, {message = "Invalid API key in request"}
    end

    ctx.consumer_id = consumer_id
    core.log.warn("hit key-auth access")
end


return _M
