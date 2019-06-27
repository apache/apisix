local lrucache = require("apisix.core.lrucache")
local schema   = require("apisix.core.schema")
local config   = require("apisix.core.config_etcd")
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
        "plugins": {
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
        for name, conf in pairs(consumer.value.plugins) do
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
    local plugin_conf = lrucache.global("/consumers",
                                        consumers.conf_version, plugin_consumer)
    return plugin_conf[plugin_name]
end


function _M.init_worker()
    local err
    consumers, err = config.new("/consumers",
                        {
                            automatic = true,
                            item_schema = schema.consumer
                        })
    if not consumers then
        error("failed to create etcd instance to fetch consumers: " .. err)
        return
    end
end


return _M
