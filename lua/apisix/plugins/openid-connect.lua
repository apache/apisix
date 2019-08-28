local core = require("apisix.core")

local plugin_name = "openid-connect"


local schema = {
    type = "object",
    properties = {
        client_id = {type = "string"},
        client_secret = {type = "string"},
        discovery = {type = "string"},
        scope = {type = "string"},
        ssl_verify = {type = "boolean"}, -- default is false
        timeout = {type = "integer", minimum = 1}, --default is 3 secs
        introspection_endpoint = {type = "string"}, --default is nil
        --default is client_secret_basic
        introspection_endpoint_auth_method = {type = "string"},
        bearer_only = {type = "boolean"}, -- default is false
        realm = {type = "string"}, -- default is apisix
        logout_path = {type = "string"}, -- default is /logout
        redirect_uri = {type = "string"}, -- default is ngx.var.request_uri
    },
    required = {"client_id", "client_secret", "discovery"}
}


local _M = {
    version = 0.1,
    priority = 2599,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if not conf.scope then
        conf.scope = 'openid'
    end
    if not conf.ssl_verify then
        conf.ssl_verify = false
    end
    if not conf.timeout then
        conf.timeout = 3
    end
    if not conf.introspection_endpoint_auth_method then
        conf.introspection_endpoint_auth_method = 'client_secret_basic'
    end
    if not conf.bearer_only then
        conf.bearer_only = false
    end
    if not conf.realm then
        conf.realm = 'apisix'
    end
    if not conf.logout_path then
        conf.logout_path = '/logout'
    end

    return true
end


function _M.access(conf, ctx)
    if not conf.redirect_uri then
        conf.redirect_uri = ctx.var.request_uri -- TODO: remove args
    end

end


return _M
