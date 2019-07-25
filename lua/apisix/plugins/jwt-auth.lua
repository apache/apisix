local core  = require("apisix.core")
local jwt   = require("resty.jwt")
local ck    = require("resty.cookie")
local ipairs= ipairs
local ngx   = ngx
local ngx_time = ngx.time
local plugin_name = "jwt-auth"


local schema = {
    type = "object",
    properties = {
        key = {type = "string"},
        secret = {type = "string"},
        algorithm = {
            type = "string",
            enum = {"HS256", "HS384", "HS512", "RS256", "ES256"}
        },
        exp = {type = "integer", minimum = 1},
    }
}


local _M = {
    version = 0.1,
    priority = 2510,
    name = plugin_name,
    schema = schema,
}


local create_consume_cache
do
    local consumer_ids = {}

    function create_consume_cache(consumers)
        core.table.clear(consumer_ids)

        for _, consumer in ipairs(consumers.nodes) do
            consumer_ids[consumer.conf.key] = consumer
        end

        return consumer_ids
    end

end -- do


function _M.check_schema(conf)
    core.log.info("input conf: ", core.json.delay_encode(conf))

    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if not conf.secret then
        conf.secret = core.id.gen_uuid_v4()
    end

    if not conf.algorithm then
        conf.algorithm = "HS256"
    end

    if not conf.exp then
        conf.exp = 60 * 60 * 24
    end

    return true
end


local function fetch_jwt_token()
    local args = ngx.req.get_uri_args()
    if args and args.jwt then
        return args.jwt
    end

    local headers = ngx.req.get_headers()
    if headers.Authorization then
        return headers.Authorization
    end

    local cookie, err = ck:new()
    if not cookie then
        return nil, err
    end

    local val, err = cookie:get("jwt")
    return val, err
end


function _M.rewrite(conf, ctx)
    local jwt_token, err = fetch_jwt_token()
    if not jwt_token then
        if err and err:sub(1, #"no cookie") ~= "no cookie" then
            core.log.error("failed to fetch JWT token: ", err)
        end

        return 401, {message = "Missing JWT token in request"}
    end

    local jwt_obj = jwt:load_jwt(jwt_token)
    core.log.info("jwt object: ", core.json.delay_encode(jwt_obj))
    if not jwt_obj.valid then
        return 401, {message = jwt_obj.reason}
    end

    local user_key = jwt_obj.payload and jwt_obj.payload.key
    if not user_key then
        return 401, {message = "missing user key in JWT token"}
    end

    local consumer_conf = core.consumer.plugin(plugin_name)
    local consumers = core.lrucache.plugin(plugin_name, "consumers_key",
            consumer_conf.conf_version,
            create_consume_cache, consumer_conf)

    local consumer = consumers[user_key]
    if not consumer then
        return 401, {message = "Invalid user key in JWT token"}
    end
    core.log.info("consumer: ", core.json.delay_encode(consumer))

    jwt_obj = jwt:verify_jwt_obj(consumer.conf.secret, jwt_obj)
    core.log.info("jwt object: ", core.json.delay_encode(jwt_obj))
    if not jwt_obj.verified then
        return 401, {message = jwt_obj.reason}
    end

    ctx.consumer_id = consumer.consumer_id
    core.log.info("hit jwt-auth rewrite")
end


local function gen_token()
    local args = ngx.req.get_uri_args()
    if not args or not args.key then
        return core.response.exit(400)
    end

    local key = args.key

    local consumer_conf = core.consumer.plugin(plugin_name)
    if not consumer_conf then
        return core.response.exit(404)
    end

    local consumers = core.lrucache.plugin(plugin_name, "consumers_key",
            consumer_conf.conf_version,
            create_consume_cache, consumer_conf)

    core.log.info("consumers: ", core.json.delay_encode(consumers))
    local consumer = consumers[key]
    if not consumer then
        return core.response.exit(404)
    end

    local jwt_token = jwt:sign(
        consumer.conf.secret,
        {
            header={
                typ = "JWT",
                alg = consumer.conf.algorithm
            },
            payload={
                key = key,
                exp = ngx_time() + consumer.conf.exp
            }
        }
    )

    core.response.exit(200, jwt_token)
end


function _M.api()
    return {
        {
            methods = {"GET"},
            uri = "/apisix/plugin/jwt/sign",
            handler = gen_token,
        }
    }
end


return _M
