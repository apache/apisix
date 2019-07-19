local core = require("apisix.core")
local route = require("resty.r3")
local get_method = ngx.req.get_method
local str_lower = string.lower
local ngx = ngx


local resources = {
    config    = require("apisix.api.config"),
}


local _M = {version = 0.1}
local router


local function check_signature(signature, timestamp, res)
    if not signature then
        return nil, "api signature is needed"
    end

    local now = os.time()
    if now - timestamp > 5 then
        return nil, "api signature expired"
    end

    local local_conf = core.config.local_conf()

    local src        = res..'|'..timestamp
    local digest     = ngx.hmac_sha1(local_conf.apisix.api_key, src)
    local str_base64 = ngx.encode_base64(digest)
    local generated  = ngx.md5(str_base64)

    if generated==signature then
        return true, nil
    end

    return nil, "signature checked fail"
end


local function run(params)

    local resource = resources[params.res]
    if not resource then
        core.response.exit(404)
    end

    local method = str_lower(get_method())
    if not resource[method] then
        core.response.exit(404)
    end

    ngx.req.read_body()
    local req_body = ngx.req.get_body_data()

    if req_body then
        local data, err = core.json.decode(req_body)
        if not data then
            core.log.error("invalid request body: ", req_body, " err: ", err)
            core.response.exit(400, {error_msg = "invalid request body",
                                     req_body = req_body})
        end

        req_body = data
    end

    --校验接口api_token
    local signature = req_body and req_body.signature or nil
    local timestamp = req_body and req_body.timestamp or nil

    local ok, err = check_signature(signature, timestamp, params.res)
    if not ok then
        core.response.exit(403)
    end

    local code, data = resource[method](params, req_body)
    if code then
        core.log.error("invalid request body: ", req_body, " err: ", err)
        core.response.exit(code, data)
    end
end


local uri_route = {
    {
        path = [[/apisix/api/{res:config}]],
        handler = run
    },
}

function _M.init_worker()
    router = route.new(uri_route)
    router:compile()
end


function _M.get()
    return router
end


return _M
