local core     = require("apisix.core")
local plugin   = require("apisix.plugin")
local error    = error
local ipairs   = ipairs
local pairs    = pairs
local consumers


local _M = {
    version = 0.2,
}


local function plugin_consumer()
    local plugins = {}

    if consumers.values == nil then
        return plugins
    end

    for _, consumer in ipairs(consumers.values) do
        for name, config in pairs(consumer.value.plugins or {}) do
            local plugin_obj = plugin.get(name)
            if plugin_obj and plugin_obj.type == "auth"
               and not plugins[name] then
                plugins[name] = {
                    nodes = {},
                    conf_version = consumers.conf_version
                }

                local new_consumer = core.table.clone(consumer.value)
                new_consumer.consumer_id = new_consumer.id
                new_consumer.auth_conf = config
                core.log.info("consumer:", core.json.delay_encode(new_consumer))
                core.table.insert(plugins[name].nodes, new_consumer)

                break
            end
        end
    end

    return plugins
end


function _M.plugin(plugin_name)
    local plugin_conf = core.lrucache.global("/consumers",
                            consumers.conf_version, plugin_consumer)
    return plugin_conf[plugin_name]
end


function _M.init_worker()
    local err
    consumers, err = core.config.new("/consumers", {
            automatic = true,
            item_schema = core.schema.consumer
        })
    if not consumers then
        error("failed to create etcd instance for fetching consumers: " .. err)
        return
    end
end


return _M
