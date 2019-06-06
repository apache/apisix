local lrucache = require("apisix.core.lrucache")
local config   = require("apisix.core.config_etcd")
local log = require("apisix.core.log")
local insert_tab = table.insert
local consumers
local error = error
local ipairs = ipairs
local pairs = pairs


local _M = {
    version = 0.1,
}

    --[[
    {
        "id": "ShunFeng",
        "plugin_config": {
            "key-auth": {
                "key": "dddxxyyy"
            }
        }
    }

    to

    {
        key-auth: [
            {
                "key": "dddxxyyy",
                "consumer_id": "ShunFeng"
            }
        ]
    }
    ]]
local function plugin_consumer()
    local plugins = {}

    if consumers.values == nil then
        return plugins
    end

    for _, consumer in ipairs(consumers.values) do
        -- log.warn("consumer: ", require("cjson").encode(consumer))
        for name, conf in pairs(consumer.value.plugin_config) do
            if not plugins[name] then
                plugins[name] = {
                    nodes = {},
                    conf_version = consumers.conf_version,
                }
            end


            insert_tab(plugins[name].nodes,
                       {consumer_id = consumer.value.id, conf = conf})
        end
    end

    return plugins
end


function _M.plugin(plugin_name)
    -- core.log.warn("conf_routes.conf_version: ", conf_routes.conf_version)
    local plugin_conf = lrucache.global("/consumers",
                                        consumers.conf_version, plugin_consumer)
    return plugin_conf[plugin_name]
end


function _M.init_worker()
    local err
    consumers, err = config.new("/consumers", {automatic = true})
    if not consumers then
        error("failed to create etcd instance to fetch upstream: " .. err)
        return
    end
end


return _M
