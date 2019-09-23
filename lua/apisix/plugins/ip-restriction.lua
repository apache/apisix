local ipairs    = ipairs
local core      = require("apisix.core")
local ipmatcher = require("resty.ipmatcher")
local str_sub   = string.sub
local str_find  = string.find
local tonumber  = tonumber
local lrucache  = core.lrucache.new({
    ttl = 300, count = 512
})


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


local function valid_ip(ip)
    local mask = 0
    local sep_pos = str_find(ip, "/", 1, true)
    if sep_pos then
        mask = str_sub(ip, sep_pos + 1)
        mask = tonumber(mask)
        if mask < 0 or mask > 128 then
            return false
        end
        ip = str_sub(ip, 1, sep_pos - 1)
    end

    if ipmatcher.parse_ipv4(ip) then
        if mask < 0 or mask > 32 then
            return false
        end
        return true
    end

    if mask < 0 or mask > 128 then
        return false
    end
    return ipmatcher.parse_ipv6(ip)
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)

    if not ok then
        return false, err
    end

    if conf.whitelist and #conf.whitelist > 0 then
        for _, cidr in ipairs(conf.whitelist) do
            if not valid_ip(cidr) then
                return false, "invalid ip address: " .. cidr
            end
        end
    end

    if conf.blacklist and #conf.blacklist > 0 then
        for _, cidr in ipairs(conf.blacklist) do
            if not valid_ip(cidr) then
                return false, "invalid ip address: " .. cidr
            end
        end
    end

    return true
end


local function create_ip_mather(ip_list)
    local ip, err = ipmatcher.new(ip_list)
    if not ip then
        core.log.error("failed to create ip matcher: ", err,
                       " ip list: ", core.json.delay_encode(ip_list))
        return nil
    end

    return ip
end


function _M.access(conf, ctx)
    local block = false
    local remote_addr = ctx.var.remote_addr

    if conf.blacklist and #conf.blacklist > 0 then
        local matcher = lrucache(conf.blacklist, nil,
                                 create_ip_mather, conf.blacklist)
        if matcher then
            block = matcher:match(remote_addr)
        end
    end

    if conf.whitelist and #conf.whitelist > 0 then
        local matcher = lrucache(conf.whitelist, nil,
                                 create_ip_mather, conf.whitelist)
        if matcher then
            block = not matcher:match(remote_addr)
        end
    end

    if block then
        return 403, { message = "Your IP address is not allowed" }
    end
end


return _M
