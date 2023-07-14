local require = require
local core = require("apisix.core")
local http = require("resty.http")
local rr_balancer = require("apisix.balancer.roundrobin")
local plugin = require("apisix.plugin")
local healthcheck = require("resty.healthcheck")
local t1k = require "resty.t1k"

local ngx = ngx
local ngx_now = ngx.now
local string = string
local fmt = string.format
local str_sub = string.sub
local str_lower = string.lower
local tostring = tostring
local tonumber = tonumber
local pairs = pairs
local ipairs = ipairs

-- module define
local plugin_name = "chaitin-waf"

local plugin_schema = {
    type = "object",
    properties = {
        upstream = {
            type = "object",
            properties = {
                servers = {
                    type = "array",
                    items = {
                        type = "string"
                    },
                    minItems = 1,
                }
            },
            required = { "servers" },
        },
    },
    required = { "upstream" },
}

local metadata_schema = {
    type = "object",
    properties = {
        nodes = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    host = {
                        type = "string",
                    },
                    port = {
                        type = "integer",
                        minimum = 1,
                        default = 80
                    },
                },
                required = { "host" }
            },
            minItems = 1,
        },
    },
    required = { "nodes" },
}

local _M = {
    version = 0.1, -- plugin version
    priority = 0, -- the priority of this plugin will be 0
    name = plugin_name, -- plugin name
    schema = plugin_schema, -- plugin schema
    metadata_schema = metadata_schema
}

local HEADER_CHAITIN_WAF = "X-APISIX-CHAITIN-WAF"
local HEADER_CHAITIN_WAF_ERROR = "X-APISIX-CHAITIN-WAF-ERROR"
local HEADER_CHAITIN_WAF_TIME = "X-APISIX-CHAITIN-WAF-TIME"
local HEADER_CHAITIN_WAF_STATUS = "X-APISIX-CHAITIN-WAF-STATUS"
local HEADER_CHAITIN_WAF_ACTION = "X-APISIX-CHAITIN-WAF-ACTION"

local cjson = require "cjson.safe".new()

local function get_server_from_metadata(metadata)
    -- TODO: healthcheck

    return metadata.nodes[1].host, metadata.nodes[1].port
end

local function get_upstream_addr(conf)
    local upstream = conf.upstream
    local servers = upstream.servers -- TODO: 多个 servers 怎么处理？？

    return servers[1]
end

function _M.access(conf, ctx)
    local extra_headers = {}

    -- 测试路由：curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
    --{
    --    "uri": "/*",
    --    "plugins": {
    --        "chaitin-waf": {
    --            "upstream": {
    --                "servers": ["www.apisix.com"],
    --            }
    --        }
    --     },
    --    "upstream": {
    --        "type": "roundrobin",
    --        "nodes": {
    --            "<UPSTREAM>:80": 1
    --        }
    --    }
    --}'
    -- 测试请求：curl localhost:9080/getid=1%20AND%201=1 -i

    local plugin_metadata = plugin.plugin_metadata(plugin_name)
    get_upstream_addr(conf)

    local metadata = plugin.plugin_metadata(plugin_name)

    -- TODO: condition

    if not core.table.try_read_attr(metadata, "value", "nodes") then
        --extra_headers[HEADER_CHAITIN_WAF] = "no"
        --core.response.set_header(extra_headers)
        --return 503, { message = "Missing metadata for chaitin-waf" }
    end

    --local host, port = get_server_from_metadata(metadata)

    -- TODO: FIXME? 实测发现请求如果不带 Host header 的话，在日志里只会显示原地址
    -- 例如：curl -H "Host: httpbin.default" localhost:9080/getid=1%20AND%201=1 -i
    -- 和：curl localhost:9080/getid=1%20AND%201=1 -i
    -- 两者在日志里显示的攻击地址不一样，如下：
    --http://localhost:9080/getid=1%20AND%201=1
    --http://httpbin.default:9080/getid=1%20AND%201=1
    -- 并且在“防护站点“里的计数并不会增加，可能是由于长亭waf没有做实际的转发只是请求了规则引擎
    local remote_addr = get_upstream_addr(conf)
    -- TODO: request id?
    local t = {
        mode = "block", -- block or monitor or off, default off
        host = "unix:/home/lingsamuel/chaitin-waf/safeline/resources/detector/snserver.sock", -- required, SafeLine WAF detection service host, unix domain socket, IP, or domain is supported, string
        port = 8000, -- required when the host is an IP or domain, SafeLine WAF detection service port, integer
        connect_timeout = 4000, -- connect timeout, in milliseconds, integer, default 1s (1000ms)
        send_timeout = 4000, -- send timeout, in milliseconds, integer, default 1s (1000ms)
        read_timeout = 4000, -- read timeout, in milliseconds, integer, default 1s (1000ms)
        req_body_size = 1024, -- request body size, in KB, integer, default 1MB (1024KB)
        keepalive_size = 256, -- maximum concurrent idle connections to the SafeLine WAF detection service, integer, default 256
        keepalive_timeout = 60000, -- idle connection timeout, in milliseconds, integer, default 60s (60000ms)
        remote_addr = "httpbin.default", -- remote address from ngx.var.VARIABLE, string, default from ngx.var.remote_addr
    }

    extra_headers[HEADER_CHAITIN_WAF] = "yes"
    ngx.log(ngx.ERR, "REQUEST TO CHAITIN: " .. remote_addr)

    local start_time = ngx_now() * 1000
    local ok, err, result = t1k.do_access(t, false)
    if not ok then
        ngx.log(ngx.ERR, "ERROR: " .. tostring(err) .. ", RESULT: " .. cjson.encode(result))

        extra_headers[HEADER_CHAITIN_WAF_ERROR] = tostring(err)
    else
        ngx.log(ngx.ERR, "OK: " .. tostring(err) .. ", RESULT: " .. cjson.encode(result))
    end
    extra_headers[HEADER_CHAITIN_WAF_TIME] = ngx_now() * 1000 - start_time

    local code = 200
    if result.status then
        extra_headers[HEADER_CHAITIN_WAF_STATUS] = code
        extra_headers[HEADER_CHAITIN_WAF_ACTION] = "reject"
        core.response.set_header(extra_headers)

        code = result.status

        local blocked_message = [[{"code": %s, "success":false, "message": "blocked message", "event_id": "%s"}]]
        return tonumber(code), fmt(blocked_message, code, result.event_id)
    end
    extra_headers[HEADER_CHAITIN_WAF_ACTION] = "pass"

    core.response.set_header(extra_headers)

    return

    -- TODO: blacklist/whitelist?
    -- TODO: captcha?
    -- TODO: 请求体过大，支持截断，例如上传文件
end

function _M.header_filter(conf, ctx)
    ngx.log(ngx.ERR, "CHAITIN: do_header_filter")
    t1k.do_header_filter()
end

function _M.body_filter(conf, ctx)
    ngx.log(ngx.ERR, "CHAITIN: do_body_filter", ngx.arg[1])
end

return _M
