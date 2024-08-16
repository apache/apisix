local _M = {}

local core = require("apisix.core")

-- globals
local DEFAULT_HOST = "api.openai.com"
local DEFAULT_PORT = 443

local path_mapper = {
    ["llm/completions"] = "/v1/completions",
    ["llm/chat"] = "/v1/chat/completions",
}


function _M.configure_request(conf, ctx)
    local ip, err = core.resolver.parse_domain(conf.model.options.upstream_host or DEFAULT_HOST)
    if not ip then
        core.log.error("failed to resolve ai_proxy upstream host: ", err)
        return core.response.exit(500)
    end
    ctx.custom_upstream_ip = ip
    ctx.custom_upstream_port = conf.model.options.upstream_port or DEFAULT_PORT

    local ups_path = (conf.model.options and conf.model.options.upstream_path)
                        or path_mapper[conf.route_type]
    ngx.var.upstream_uri = ups_path
    ngx.var.upstream_scheme = "https" -- TODO: allow override for tests
    ngx.var.upstream_host = conf.model.options.upstream_host
                            or DEFAULT_HOST -- TODO: sanity checks. encapsulate to a func
    ctx.custom_balancer_host = conf.model.options.upstream_host or DEFAULT_HOST
    ctx.custom_balancer_port = conf.model.options.port or DEFAULT_PORT

    local auth_header_name = conf.auth and conf.auth.header_name
    local auth_header_value = conf.auth and conf.auth.header_value
    local auth_param_name = conf.auth and conf.auth.param_name
    local auth_param_value = conf.auth and conf.auth.param_value
    local auth_param_location = conf.auth and conf.auth.param_location

    -- TODO: simplify auth structure
    if auth_header_name and auth_header_value then
        core.request.set_header(ctx, auth_header_name, auth_header_value)
    end

    -- TODO: test uris
    if auth_param_name and auth_param_value and auth_param_location == "query" then
        local query_table = core.request.get_uri_args(ctx)
        query_table[auth_param_name] = auth_param_value
        core.request.set_uri_args(query_table)
    end

    return true, nil
end

return _M
