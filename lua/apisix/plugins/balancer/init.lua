local resty_roundrobin = require("resty.roundrobin")
local balancer = require("ngx.balancer")
local apisix = require("apisix")
local ngx = ngx
local ngx_exit = ngx.exit


local plugin_name = "balancer"


local _M = {
    version = 0.1,
    name = plugin_name,
}

    -- conf = {
    --     upstream_id = 3
    --     id = 3,
    -- }
function _M.upstream(conf, version)
    -- it should be a single plugin
    local upstream_nodes = {
        ["220.181.57.216:80"] = 1,
        ["220.181.57.215:80"] = 1,
        ["220.181.57.217:80"] = 1,
    }
    local upstream = conf[plugin_name .. "_upstream"]
    if not upstream then
        upstream = resty_roundrobin:new(upstream_nodes)
        conf[plugin_name .. "_upstream"] = upstream
    end

    local server = upstream:find()
    apisix.log.warn("fetched server: ", server)

    local ok, err = balancer.set_current_peer(server)
    if not ok then
        apisix.log.error("failed to set the current peer: ", err)
        ngx_exit(ngx.ERROR)
        return
    end
end


return _M
