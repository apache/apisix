local ipairs = ipairs

local core = require("apisix.core")
local iputils = require("resty.iputils")


local schema = {
    type = "object",
    properties = {
        whitelist = {
            type = "array",
            items = {type = "string"},
            minItems = 1
        },
        blacklist = {
            type = "array",
            items = {type = "string"},
            minItems = 1
        }
    },
    oneOf = {
        {required = {"whitelist"}},
        {required = {"blacklist"}}
    }
}


local plugin_name = "ip-restriction"


local _M = {
    version = 0.1,
    priority = 3000,        -- TODO: add a type field, may be a good idea
    name = plugin_name,
    schema = schema,
}


-- TODO: support IPv6
local function validate_cidr_v4(ip)
    local lower, err = iputils.parse_cidr(ip)
    if not lower and err then
        return nil, "invalid cidr range: " .. err
    end

    return true
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)

    if not ok then
        return false, err
    end

    if conf.whitelist and #conf.whitelist > 0 then
        for _, cidr in ipairs(conf.whitelist) do
            ok, err = validate_cidr_v4(cidr)
            if not ok then
                return false, err
            end
        end
    end

    if conf.blacklist and #conf.blacklist > 0 then
        for _, cidr in ipairs(conf.blacklist) do
            ok, err = validate_cidr_v4(cidr)
            if not ok then
                return false, err
            end
        end
    end

    return true
end


local function create_cidrs(ip_list)
    local parsed_cidrs = core.table.new(#ip_list, 0)
    for i, cidr in ipairs(ip_list) do
        local lower, upper = iputils.parse_cidr(cidr)
        if not lower and upper then
            local err = upper
            return nil, "invalid cidr range: " .. err
        end
        parsed_cidrs[i] = {lower, upper}
    end

    return parsed_cidrs
end


function _M.access(conf, ctx)
    local block = false
    local binary_remote_addr = ctx.var.binary_remote_addr

    if conf.blacklist and #conf.blacklist > 0 then
        local name = plugin_name .. 'black'
        local parsed_cidrs = core.lrucache.plugin_ctx(name, ctx, create_cidrs,
                                                      conf.blacklist)
        block = iputils.binip_in_cidrs(binary_remote_addr, parsed_cidrs)
    end

    if conf.whitelist and #conf.whitelist > 0 then
        local name = plugin_name .. 'white'
        local parsed_cidrs = core.lrucache.plugin_ctx(name, ctx, create_cidrs,
                                                      conf.whitelist)
        block = not iputils.binip_in_cidrs(binary_remote_addr, parsed_cidrs)
    end

    if block then
        return 403, { message = "Your IP address is not allowed" }
    end
end


return _M
