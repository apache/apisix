local core = require("apisix.core")
local services
local error = error


local _M = {
    version = 0.1,
}


function _M.get(service_id)
    return services:get(service_id)
end


function _M.init_worker()
    local err
    services, err = core.config.new("/services",
                        {
                            automatic = true,
                            item_schema = core.schema.service
                        })
    if not services then
        error("failed to create etcd instance to fetch upstream: " .. err)
        return
    end
end


return _M
