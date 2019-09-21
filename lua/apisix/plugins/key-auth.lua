local core     = require("apisix.core")
local consumer = require("apisix.consumer")
local plugin_name = "key-auth"
local ipairs   = ipairs


local schema = {
    type = "object",
    properties = {
        key = {type = "string"},
    }
}


local _M = {
    version = 0.1,
    priority = 2500,
    type = 'auth',
    name = plugin_name,
    schema = schema,
}


local create_consume_cache
do
    local consumer_ids = {}

    function create_consume_cache(consumers)
        core.table.clear(consumer_ids)

        for _, consumer in ipairs(consumers.nodes) do
            core.log.info("consumer node: ", core.json.delay_encode(consumer))
            consumer_ids[consumer.auth_conf.key] = consumer
        end

        return consumer_ids
    end

end -- do


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


function _M.rewrite(conf, ctx)
    local key = core.request.header(ctx, "apikey")
    if not key then
        return 401, {message = "Missing API key found in request"}
    end

    local consumer_conf = consumer.plugin(plugin_name)
    if not consumer_conf then
        return 401, {message = "Missing related consumer"}
    end

    local consumers = core.lrucache.plugin(plugin_name, "consumers_key",
            consumer_conf.conf_version,
            create_consume_cache, consumer_conf)

    local consumer = consumers[key]
    if not consumer then
        return 401, {message = "Invalid API key in request"}
    end
    core.log.info("consumer: ", core.json.delay_encode(consumer))

    ctx.consumer = consumer
    ctx.consumer_id = consumer.consumer_id
    core.log.info("hit key-auth rewrite")
end


return _M
