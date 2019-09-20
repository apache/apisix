local ipairs = ipairs
local pcall = pcall
local loadstring = loadstring
local require = require
local type = type

return function(plugin_name, priority)
    local core = require("apisix.core")

    local schema = {
        type = "object",
        properties = {
            phase = {
                type = "string",
                -- the default phase is access
                enum = {"rewrite", "access", "header_filer", "body_filter",
                        "log", "balancer"}
            },
            functions = {
                type = "array",
                items = {type = "string"},
                minItems = 1
            },
        },
        required = {"functions"}
    }

    local _M = {
        version = 0.1,
        priority = priority,
        name = plugin_name,
    }

    local function load_funcs(functions)
        local funcs = core.table.new(#functions, 0)

        local index = 1
        for _, func_str in ipairs(functions) do
            local _, func = pcall(loadstring(func_str))
            funcs[index] = func
            index = index + 1
        end

        return funcs
    end

    local function call_funcs(phase, conf, ctx)
        if phase ~= conf.phase then
            return
        end

        local functions = core.lrucache.plugin_ctx(plugin_name, ctx,
                                                   load_funcs, conf.functions)

        for _, func in ipairs(functions) do
            func()
        end
    end

    function _M.check_schema(conf)
        local ok, err = core.schema.check(schema, conf)
        if not ok then
            return false, err
        end

        if not conf.phase then
            conf.phase = 'access'
        end

        local functions = conf.functions
        for _, func_str in ipairs(functions) do
            local func, err = loadstring(func_str)
            if err then
                return false, 'failed to loadstring: ' .. err
            end

            local ok, ret = pcall(func)
            if not ok then
                return false, 'pcall error: ' .. ret
            end
            if type(ret) ~= 'function' then
                return false, 'only accept Lua function,'
                               .. ' the input code type is ' .. type(ret)
            end
        end

        return true
    end

    function _M.rewrite(conf, ctx)
        call_funcs('rewrite', conf, ctx)
    end

    function _M.access(conf, ctx)
        call_funcs('access', conf, ctx)
    end

    function _M.balancer(conf, ctx)
        call_funcs('balancer', conf, ctx)
    end

    function _M.header_filer(conf, ctx)
        call_funcs('header_filer', conf, ctx)
    end

    function _M.body_filter(conf, ctx)
        call_funcs('body_filter', conf, ctx)
    end

    function _M.log(conf, ctx)
        call_funcs('log', conf, ctx)
    end

    return _M
end
