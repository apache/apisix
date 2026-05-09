local lua_load = load
local ipairs = ipairs
local pcall = pcall

local core = require("apisix.core")

local lrucache = core.lrucache.new({
    ttl = 300, count = 512
})

local schema = {
    type = "object",
    properties = {
    functions = {
        type = "array",
            items = {
                type = "string",
            },
        },
    },
    required = {"functions"},
}

local _M = {
    version = 0.1,
    priority = 9999999,
    name = "exit-transformer",
    schema = schema
}

function _M.check_schema(conf)
    local data_valid, err = core.schema.check(schema, conf)
    if not data_valid then
        return false, err
    end
    for _, lua_code_func in ipairs(conf.functions) do
        local _ , err = lua_load(lua_code_func)
        if err then
             return false, err
        end
    end
    return true
end


local function exit_callback(resp_code, resp_body, resp_header, lua_code_func)
    local safe_loaded_func, err = lrucache(lua_code_func, nil, lua_load, lua_code_func)
    if err then
        core.log.error("failed to load lua code: ", err)
        return resp_code, resp_body, resp_header
    end

    local ok, err_or_new_resp_code, new_resp_body, new_resp_header
                = pcall(safe_loaded_func, resp_code, resp_body, resp_header)
    if not ok then
        core.log.error("failed to run lua code: ", err_or_new_resp_code)
        return resp_code, resp_body, resp_header
    end

    return err_or_new_resp_code, new_resp_body, new_resp_header
end


function _M.rewrite(conf)
    for _, lua_code_func in ipairs(conf.functions) do
        core.response.exit_insert_callback(exit_callback, lua_code_func)
    end
end


return _M
