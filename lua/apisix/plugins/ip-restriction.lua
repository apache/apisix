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

local cache = {}


-- TODO: support IPv6
local function validate_cidr_v4(ip)
    local lower, err = iputils.parse_cidr(ip)
    if not lower and err then
        return nil, "invalid cidr range: " .. err
    end

    return true
end


local function cidr_cache(cidr_tab)
    local cidr_tab_len = #cidr_tab

    -- table of parsed cidrs to return
    local parsed_cidrs = core.table.new(cidr_tab_len, 0)

    -- build a table of parsed cidr blocks based on configured
    -- cidrs, either from cache or via iputils parse
    for i = 1, cidr_tab_len do
        local cidr        = cidr_tab[i]
        local parsed_cidr = cache[cidr]

        if parsed_cidr then
            parsed_cidrs[i] = parsed_cidr
        else
            -- if we dont have this cidr block cached,
            -- parse it and cache the results
            local lower, upper = iputils.parse_cidr(cidr)

            cache[cidr] = { lower, upper }
            parsed_cidrs[i] = cache[cidr]
        end
    end

    return parsed_cidrs
end


function _M.init()
    local ok, err = iputils.enable_lrucache()
    if not ok then
        core.log.error("could not enable lrucache for iputils: ", err)
    end
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


function _M.access(conf, ctx)
    local block = false
    local binary_remote_addr = ctx.var.binary_remote_addr

    if conf.blacklist and #conf.blacklist > 0 then
        block = iputils.binip_in_cidrs(binary_remote_addr,
                                       cidr_cache(conf.blacklist))
    end

    if conf.whitelist and #conf.whitelist > 0 then
        block = not iputils.binip_in_cidrs(binary_remote_addr,
                                           cidr_cache(conf.whitelist))
    end

    if block then
        return 403, { message = "Your IP address is not allowed" }
    end
end


return _M
