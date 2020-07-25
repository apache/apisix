
local etcd = require('apisix.core.etcd')
local ngx_timer_at       = ngx.timer.at
local ngx_timer_every    = ngx.timer.every

local applications
local discovery_key = "service_dicovery"

local schema = {
    type = "object",
    properties = {
        service_name = { type = "string", maxLength = 256 }
    },
    anyOf = {
        { require = { 'service_name' }}
    },
}

local _M = {
    version = 0.1,
    schema = schema,
}

local function fetch_full_registry(premature)

    if premature then
        return
    end

    local res = etcd.get(discovery_key)
    applications = res.body.node.value
end

function _M.nodes(up_conf)
    return { [1] = applications[up_conf.etcd.service_name]}
end

function _M.init_worker()
    ngx_timer_at(0, fetch_full_registry)
    ngx_timer_every(30, fetch_full_registry)
end

return _M