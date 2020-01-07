local core = require("apisix.core")
local ngx = ngx
local ngx_re = require("ngx.re")
local json = require("apisix.core.json")

local authorizations_etcd

local lrucache = core.lrucache.new({
    ttl = 300, count = 512
})

-- You can follow this document to write schema:
-- https://github.com/Tencent/rapidjson/blob/master/bin/draft-04/schema
-- rapidjson not supported `format` in draft-04 yet
local schema = {
    type = "object",
    properties = {
        enable = { type = "boolean", default = true, enum = { true, false } },
    },
}

local plugin_name = "basic-auth"

local function gen_key(username)
    local key = "/authorizations/" .. username
    return key
end

local _M = {
    version = 0.1,
    priority = 1802,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)

    if not ok then
        return false, err
    end

    return true
end

local function extract_auth_header(authorization)

    local function do_extract(auth)
        local obj = { username = "", password = "" }

        local m, err = ngx.re.match(auth, "Basic\\s(.+)")
        if err then
            -- error authorization
            return nil, err
        end

        local decoded = ngx.decode_base64(m[1])

        local res
        res, err = ngx_re.split(decoded, ":")
        if err then
            return nil, "split authorization err:" .. err
        end

        obj.username = ngx.re.gsub(res[1], "\\s+", "")
        obj.password = ngx.re.gsub(res[2], "\\s+", "")
        core.log.info("plugin access phase, authorization: ", obj.username, ": ", obj.password)

        return obj, nil
    end

    local matcher, err = lrucache(authorization, nil, do_extract, authorization)

    if matcher then
        return matcher.username, matcher.password, err
    else
        return "", "", err
    end


end

function _M.access(conf, ctx)
    core.log.info("plugin access phase, conf: ", core.json.delay_encode(conf))

    -- 0. check the plugin is enabled
    if not conf.enable then
        return
    end


    -- 1. extract authorization from header
    local headers = ngx.req.get_headers()
    if not headers.Authorization then
        return 401, { message = "authorization is required" }
    end

    local username, password, err = extract_auth_header(headers.Authorization)
    if err then
        return 401, { message = err }
    end

    -- 2. get user info from etcd
    local res = authorizations_etcd:get(username)
    if res == nil then
        return 401, { message = "failed to find authorization from etcd" }
    end

    -- 3. check user exists
    if not res.value or not res.value.id then
        return 401, { message = "user is not found" }
    end

    local value = res.value
    core.log.info("etcd value: ", core.json.delay_encode(value))

    -- 4. check the password is correct
    if value.password ~= password then
        return 401, { message = "password is error" }
    end


    core.log.info("hit basic-auth access")
end


local function set_auth()
    local body_table = {}
    -- read_body can not use in log_by_lua
    if ngx.re.find(ngx.req.get_headers()["Content-Type"] or "", "application/json") then
        ngx.req.read_body()

        local body_data = ngx.req.get_body_data()
        if body_data ~= nil then
            body_table = json.decode(body_data)
        end

    else
        body_table = ngx.req.get_post_args()
    end

    local username = body_table["username"]
    local password = body_table["password"]

    if not username or not password then
        core.response.exit(200, "username,password is required")
    end

    local key = gen_key(username)

    local res, err = core.etcd.set(key, { username = username, password = password })
    if not res then
        core.response.exit(500, err)
    end

    core.response.exit(res.status, res.body)
end

local function get_auth()
    local request_table = ngx.req.get_uri_args() or {}

    if not request_table["username"] then
        core.response.exit(200, "username is required")
    end

    local username = request_table["username"]

    local key = gen_key(username)

    local res, err = core.etcd.get(key)
    if not res then
        core.response.exit(500, err)
    end

    core.response.exit(res.status, res.body)
end

-- curl 'http://127.0.0.1:9080/apisix/plugin/basic-auth/set' -H "Content-Type:application/json" -d '{"username":"foo","password":"bar"}'

function _M.api()
    return {
        {
            methods = { "GET" },
            uri = "/apisix/plugin/basic-auth/get",
            handler = get_auth,
        },
        {
            methods = { "POST", "PUT" },
            uri = "/apisix/plugin/basic-auth/set",
            handler = set_auth,
        }
    }
end

local appkey_scheme = {
    type = "object",
    properties = {
        username = {
            description = "username",
            type = "string",
        },
        password = {
            type = "string",
        }
    },
}

function _M.init()

    authorizations_etcd, err = core.config.new("/authorizations", {
        automatic = true,
        item_schema = appkey_scheme
    })

    if not authorizations_etcd then
        -- @todo log
        error("failed to create etcd instance for fetching authorizations: " .. err)
        return
    end

    core.log.info("hit authorizations_etcd init")

end

return _M
