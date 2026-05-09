local core          = require("apisix.core")
local proxy_rewrite = require("apisix.plugins.proxy-rewrite")
local expr          = require("resty.expr.v1")
local roundrobin    = require("resty.roundrobin")
local ipairs        = ipairs
local pairs         = pairs

local lrucache = core.lrucache.new({
    ttl = 0, count = 512
})


local schema = {
    type = "object",
    properties = {
        rules = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    match = {
                        type = "array",
                        items = {
                            anyOf = {
                                {
                                    type = "array",
                                },
                                {
                                    type = "string",
                                },
                            }
                        },
                        minItems = 1,
                    },
                    actions = {
                        type = "array",
                        items = {
                            type = "object",
                            properties = {
                                set_headers = {
                                    description = "new headers for request",
                                    type = "object",
                                    minProperties = 1,
                                },
                                weight = {
                                    type = "integer",
                                    default = 1,
                                    minimum = 1,
                                },
                            },
                        },
                        minItems = 1,
                    },
                },
                required = {"actions"}
            },
            minItems = 1,
        }
    },
    required = {"rules"}
}

local plugin_name = "traffic-label"

local _M = {
    version = 0.1,
    -- priority: fault-injection proxy-mirror *-auth > traffic-label > traffic-split
    priority = 995,
    name = plugin_name,
    schema = schema
}


local function check_set_headers_schema(conf)
    local header_conf = {
        headers = conf
    }

    return proxy_rewrite.check_schema(header_conf)
end


local function set_req_headers(header_conf, ctx)
    local conf = {
        headers = header_conf
    }

    -- reuse proxy-rewrite plugin's logic
    if conf.headers then
        if not conf.headers_arr then
            conf.headers_arr = {}

            for field, value in pairs(conf.headers) do
                core.table.insert_tail(conf.headers_arr, field, value)
            end
        end

        local field_cnt = #conf.headers_arr
        for i = 1, field_cnt, 2 do
            core.request.set_header(ctx, conf.headers_arr[i],
                                    core.utils.resolve_var(conf.headers_arr[i+1], ctx.var))
        end
    end
end


local support_action = {
    ["set_headers"] = {
        check_schema = check_set_headers_schema,
        handle = set_req_headers
    }
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    for _, rule in ipairs(conf.rules) do
        local ok, err = expr.new(rule.match or {})
        if not ok then
            return false, "failed to validate the 'match' expression: " ..
                            core.json.encode(rule.match) .. " err: " .. err
        end

        for _, action in ipairs(rule.actions) do
            for name, conf in pairs(action) do
                if name == "weight" then
                    goto CONTINUE
                end

                local item = support_action[name]
                if not item then
                    return false, "not supported action: " .. name
                end

                local ok, err = support_action[name].check_schema(conf)
                if not ok then
                    return false, "failed to validate the '" .. name .. "' action: " .. err
                end

                ::CONTINUE::
            end
        end
    end

    return true
end


local function new_rr_obj(actions)
    local id_weight_map = {}
    for i, action in ipairs(actions) do
        id_weight_map[i] = action.weight
    end

    return roundrobin:new(id_weight_map)
end


local function next_action(actions)
    local rr_up, err = lrucache(actions, nil, new_rr_obj, actions)
    if not rr_up then
        core.log.error("lrucache roundrobin failed: ", err)
        return false
    end

    local id = rr_up:find()
    return actions[id]
end


function _M.access(conf, ctx)
    local match_result

    if not conf.rules_arr then
        conf.rules_arr = {}

        for _, rule in ipairs(conf.rules) do
            -- if no rule.match, use {} to match all request
            local expr, _ = expr.new(rule.match or {})
            core.table.insert_tail(conf.rules_arr, expr)
        end
    end

    for i, rule in ipairs(conf.rules) do
        local expr = conf.rules_arr[i]
        match_result = expr:eval(ctx.var)

        if match_result then
            local action = next_action(rule.actions)
            -- only one action is currently supported
            for name, conf in pairs(action) do
                if name ~= "weight" then
                    return support_action[name].handle(conf, ctx)
                end
            end
        end
    end
end


return _M
