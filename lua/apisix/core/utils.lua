local table    = require("apisix.core.table")
local ngx_re   = require("ngx.re")
local resolver = require("resty.dns.resolver")
local ipmatcher= require("resty.ipmatcher")
local open     = io.open
local math     = math
local sub_str  = string.sub
local find_str = string.find
local tonumber = tonumber


local _M = {
    version = 0.2,
    parse_ipv4 = ipmatcher.parse_ipv4,
    parse_ipv6 = ipmatcher.parse_ipv6,
}


function _M.get_seed_from_urandom()
    local frandom, err = open("/dev/urandom", "rb")
    if not frandom then
        return nil, 'failed to open /dev/urandom: ' .. err
    end

    local str = frandom:read(4)
    frandom:close()
    if not str then
        return nil, 'failed to read data from /dev/urandom'
    end

    local seed = 0
    for i = 1, 4 do
        seed = 256 * seed + str:byte(i)
    end
    return seed
end


function _M.split_uri(uri)
    return ngx_re.split(uri, "/")
end


function _M.dns_parse(resolvers, domain)
    local r, err = resolver:new{
        nameservers = table.clone(resolvers),
        retrans = 5,  -- 5 retransmissions on receive timeout
        timeout = 2000,  -- 2 sec
    }

    if not r then
        return nil, "failed to instantiate the resolver: " .. err
    end

    local answers, err = r:query(domain, nil, {})
    if not answers then
        return nil, "failed to query the DNS server: " .. err
    end

    if answers.errcode then
        return nil, "server returned error code: " .. answers.errcode
                    .. ": " .. answers.errstr
    end

    local idx = math.random(1, #answers)
    return answers[idx]
end


function _M.parse_addr(addr)
    local pos = find_str(addr, ":", 1, true)
    if not pos then
        return addr, 80
    end

    local host = sub_str(addr, 1, pos - 1)
    local port = sub_str(addr, pos + 1)
    return host, tonumber(port)
end


return _M
