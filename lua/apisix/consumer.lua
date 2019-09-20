local lrucache = require("apisix.core.lrucache")
local schema   = require("apisix.core.schema")
local config   = require("apisix.core.config_etcd")
local log      = require("apisix.core.log")
local tab      = require("apisix.core.table")
local json     = require("apisix.core.json")
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
        for name, config in pairs(consumer.value.auth_plugin or {}) do
            if not plugins[name] then
                plugins[name] = {
                    nodes = {},
                    conf_version = consumers.conf_version
                }

                local new_consumer = tab.clone(consumer.value)
                new_consumer.consumer_id = new_consumer.id
                new_consumer.auth_conf = config
                log.info("new consumer: ", json.delay_encode(new_consumer))
                tab.insert(plugins[name].nodes, new_consumer)
            end
        end
    end

    return plugins
end


function _M.plugin(plugin_name)
    local plugin_conf = lrucache.global("/consumers",
                            consumers.conf_version, plugin_consumer)
    return plugin_conf[plugin_name]
end


function _M.init_worker()
    local err
    consumers, err = config.new("/consumers", {
            automatic = true,
            item_schema = schema.consumer
        })
    if not consumers then
        error("failed to create etcd instance for fetching consumers: " .. err)
        return
    end
end


return _M
