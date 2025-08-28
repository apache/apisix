local require       = require
local core          = require("apisix.core")
local next          = next
local ipairs        = ipairs

local trusted_addresses_matcher

local _M = {}


local function validate_trusted_addresses(trusted_addresses)
    for _, cidr in ipairs(trusted_addresses) do
        if not core.ip.validate_cidr_or_ip(cidr) then
            core.log.error("Invalid IP/CIDR '", cidr, "' exists in trusted_addresses")
            return false
        end
    end
    return true
end


function _M.init_worker()
    local local_conf = core.config.local_conf()
    local trusted_addresses = core.table.try_read_attr(local_conf, "apisix", "trusted_addresses")

    if not trusted_addresses then
        return
    end

    if not core.table.isarray(trusted_addresses) then
        core.log.error("trusted_addresses '", trusted_addresses, "' is not an array, please check your configuration")
        return
    end

    if not next(trusted_addresses) then
        core.log.info("trusted_addresses is an empty array")
        return
    end

    if not validate_trusted_addresses(trusted_addresses) then
        return
    end

    local matcher, err = core.ip.create_ip_matcher(trusted_addresses)
    if not matcher then
        core.log.error("failed to create ip matcher for trusted_addresses: ", err)
        return
    end

    trusted_addresses_matcher = matcher
end


function _M.is_trusted(address)
    if not trusted_addresses_matcher then
        core.log.info("trusted_addresses_matcher is not initialized, skipping subsequent parsing.")
        return false
    end
    return trusted_addresses_matcher:match(address)
end

return _M
