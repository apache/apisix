local ngx = ngx
local apisix = require("apisix")
local base_plugin = apisix.base_plugin
local balancer = require("ngx.balancer")
local resty_roundrobin = require "resty.roundrobin"
local encode_json = require("cjson.safe").encode
local ngx_exit = ngx.exit


-- TODO: need a more powerful way to define the schema
local args_schema = {
    i = "int",
    s = "string",
    t = "table",
}


local plugin_name = "example-plugin"

local _M = {
    version = 0.1,
    priority = 1000,        -- TODO: add a type field, may be a good idea
    name = plugin_name,
}


function _M.check_args(conf)
    local ok, err = base_plugin.check_args(conf, args_schema)
    if not ok then
        return false, err
    end

    -- add more restriction rules if we needs

    return true
end


function _M.rewrite(conf)
    -- apisix.log.warn("plugin rewrite phase, conf: ", encode_json(conf))
end


function _M.access(conf)
    -- apisix.log.warn("plugin access phase, conf: ", encode_json(conf))
end


function _M.upstream(conf)
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
