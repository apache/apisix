local core   = require("apisix.core")
local pairs  = pairs
local type   = type
local ngx    = ngx
local plugin = require("apisix.plugin")


local _M = {
    version = 0.1,
    priority = 412,
    conf = {
        ["limit-count_1"] = {
            count = 2,
            time_window = 60,
            rejected_code = 503,
            key = "remote_addr"
        },
        ["response-rewrite_1"] = {
            body = {
                code = "ok",
                message = "new json body"
            },
            headers = {
                ["X-limit-status"] = "limited"
            }
        },
        ["response-rewrite_2"] = {
            body = {
                code = "ok",
                message = "new json body2"
            },
            headers = {
                ["X-limit-status"] = "pass"
            }
        }
    },
    plugins = {},
}


function _M.access(api_ctx)
    -- 1
    local limit_count = plugin.get("limit-count")
    local condition_fun1 = limit_count["access"] and limit_count["access"] or limit_count["rewrite"]
    -- 2
    local response_rewrite = plugin.get("response-rewrite")
    local condition_fun2 = response_rewrite["access"] and response_rewrite["access"] or response_rewrite["rewrite"]

    core.log.info("test access")

    local code, body = nil, nil
    if condition_fun1 then
        code, body = condition_fun1(_M.conf["limit-count_1"], api_ctx)
    end

    core.log.info("test access2")

    -- save ordered plugins
    core.table.insert(_M.plugins, "limit-count")
    core.table.insert(_M.plugins, "limit-count_1")

    if code == 503 then
        core.log.info("test access3")
        if condition_fun2 then
            core.log.info("test access33")
            condition_fun2(_M.conf["response-rewrite_1"], api_ctx)
        end
        -- save ordered plugins
        core.table.insert(_M.plugins, "response-rewrite")
        core.table.insert(_M.plugins, "response-rewrite_1")
    else
        core.log.info("test access4")
        if condition_fun2 then
            core.log.info("test access44")
            condition_fun2(_M.conf["response-rewrite_2"], api_ctx)
        end
        -- save ordered plugins
        core.table.insert(_M.plugins, "response-rewrite")
        core.table.insert(_M.plugins, "response-rewrite_2")
        core.log.info("test access5")
    end

end


function _M.header_filter(ctx)
    local plugin_count = #_M.plugins
    core.log.info("test header filter plugin count: ", plugin_count)
    for i = 1, plugin_count, 2 do
        core.log.info("header i:", i)
        core.log.info("header i + 1:", i + 1)
        local plugin_name = _M.plugins[i]
        local plugin_conf_name = _M.plugins[i + 1]
        core.log.info("test header filter plugin_name: ", plugin_name)
        core.log.info("test header filter plugin_conf_name: ", plugin_conf_name)
        local plugin_obj = plugin.get(plugin_name)
        core.log.info("test header filter plugin_obj: ", core.json.delay_encode(plugin_obj, true))
        local phase_fun = plugin_obj["header_filter"]
        core.log.info("test header phase_fun: ", core.json.delay_encode(phase_fun, true))
        if phase_fun then
            core.log.info("test header filter")
            local code, body = phase_fun(_M.conf[plugin_conf_name], api_ctx)
            if code or body then
                -- do we exit here?
                core.log.info("test header filter2")
                core.response.exit(code, body)
            end
        end
    end
end


function _M.body_filter(ctx)
    core.log.info("test body filter plugin count: ", #_M.plugins)
    for i = 1, #_M.plugins, 2 do
        local plugin_name = _M.plugins[i]
        local plugin_conf_name = _M.plugins[i + 1]

        local plugin_obj = plugin.get(plugin_name)
        local phase_fun = plugin_obj["body_filter"]

        core.log.info("test body filter plugin_name: ", plugin_name)
        core.log.info("test body filter plugin_conf_name: ", plugin_conf_name)
        core.log.info("test body filter plugin_obj: ", core.json.delay_encode(plugin_obj, true))

        if phase_fun then
            core.log.info("test body filter")
            local code, body = phase_fun(_M.conf[plugin_conf_name], api_ctx)
            if code or body then
                -- do we exit here?
                core.log.info("test body filter2")
                core.response.exit(code, body)
            end
        end
    end
end


function _M.log(ctx)
    for i = 1, #_M.plugins, 2 do
        local plugin_name = _M.plugins[i]
        local plugin_conf_name = _M.plugins[i + 1]

        local plugin_obj = plugin.get(plugin_name)
        local phase_fun = plugin_obj["log"]
        if phase_fun then
            local code, body = phase_fun(_M.conf[plugin_conf_name], api_ctx)
            if code or body then
                -- do we exit here?
                core.response.exit(code, body)
            end
        end
    end
end


return _M
