local core = require("apisix.core")
local ngx_re = require("ngx.re")
local openidc = require("resty.openidc")
local ngx = ngx
local ngx_encode_base64 = ngx.encode_base64

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


local function has_bearer_access_token(ctx)
    local auth_header = core.request.header(ctx, "Authorization")
    if not auth_header then
        return false
    end

    local res, err = ngx_re.split(auth_header, " ", nil, nil, 2)
    if not res then
        return false, err
    end

    if res[1] == "bearer" then
        return true
    end

    return false
end


local function introspect(ctx, conf)
    if has_bearer_access_token(ctx) or conf.bearer_only then
        local res, err = openidc.introspect(conf)
        if res then
            return res
        end
        if conf.bearer_only then
            ngx.header["WWW-Authenticate"] = 'Bearer realm="' .. conf.realm .. '",error="' .. err .. '"'
            return core.response.exit(ngx.HTTP_UNAUTHORIZED, err)
        end
    end

    return nil
end


local function add_user_header(user)
    local userinfo = core.json.encode(user)
    ngx.req.set_header("X-Userinfo", ngx_encode_base64(userinfo))
end


local function make_oidc(conf)
    local res, err = openidc.authenticate(conf)
    if err then
        return core.response.exit(500, err)
    end
    return res
end


function _M.access(conf, ctx)
    if not conf.redirect_uri then
        conf.redirect_uri = ctx.var.request_uri -- TODO: remove args
    end

    local response
    if conf.introspection_endpoint then
        response = introspect(ctx, conf)
        if response then
            add_user_header(response)
        end
    end

    if not response then
        response = make_oidc(conf)
        if response then
            if response.user then
                add_user_header(response.user)
            end
            if response.access_token then
                ngx.req.set_header("X-Access-Token", response.access_token)
            end
            if response.id_token then
                local token = core.json.encode(response.id_token)
                ngx.req.set_header("X-ID-Token", ngx.encode_base64(token))
            end
        end
    end
end


return _M
