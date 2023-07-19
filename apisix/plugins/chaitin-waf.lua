local require = require
local core = require("apisix.core")
local http = require("resty.http")
local rr_balancer = require("apisix.balancer.roundrobin")
local plugin = require("apisix.plugin")
local healthcheck = require("resty.healthcheck")
local t1k = require "resty.t1k"
local expr       = require("resty.expr.v1")

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

local vars_schema = {
    type = "array",
}

local match_schema = {
    type = "array",
    items = {
        type = "object",
        properties = {
            vars = vars_schema
        }
    },
}

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
                },
            },
            required = { "servers" },
        },
        match = match_schema,
    },
    required = { "upstream" },
}

local health_checker = {
    type = "object",
    properties = {
        active = {
            type = "object",
            properties = {
                type = {
                    type = "string",
                    enum = { "http", "https", "tcp" },
                    default = "http"
                },
                timeout = { type = "number", default = 1 },
                concurrency = { type = "integer", default = 10 },
                host = core.schema.host_def,
                port = {
                    type = "integer",
                    minimum = 1,
                    maximum = 65535
                },
                http_path = { type = "string", default = "/" },
                https_verify_certificate = { type = "boolean", default = true },
                healthy = {
                    type = "object",
                    properties = {
                        interval = { type = "integer", minimum = 1, default = 1 },
                        http_statuses = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "integer",
                                minimum = 200,
                                maximum = 599
                            },
                            uniqueItems = true,
                            default = { 200, 302 }
                        },
                        successes = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 2
                        }
                    }
                },
                unhealthy = {
                    type = "object",
                    properties = {
                        interval = { type = "integer", minimum = 1, default = 1 },
                        http_statuses = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "integer",
                                minimum = 200,
                                maximum = 599
                            },
                            uniqueItems = true,
                            default = { 429, 404, 500, 501, 502, 503, 504, 505 }
                        },
                        http_failures = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 5
                        },
                        tcp_failures = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 2
                        },
                        timeouts = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 3
                        }
                    }
                },
                req_headers = {
                    type = "array",
                    minItems = 1,
                    items = {
                        type = "string",
                        uniqueItems = true,
                    },
                }
            }
        }
    },
    { required = { "active" } },
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
        checks = health_checker,
    },
    required = { "nodes" },
}

local global_server_picker
local global_healthcheck = {}

local _M = {
    version = 0.1, -- plugin version
    priority = 0, -- the priority of this plugin will be 0
    name = plugin_name, -- plugin name
    schema = plugin_schema, -- plugin schema
    metadata_schema = metadata_schema
}

function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end

    local ok, err = core.schema.check(plugin_schema, conf)

    if not ok then
        return false, err
    end

    if conf.match then
        for _, m in ipairs(conf.match) do
            local ok, err = expr.new(m.vars)
            if not ok then
                return false, "failed to validate the 'vars' expression: " .. err
            end
        end
    end

    return true
end

local HEADER_CHAITIN_WAF = "X-APISIX-CHAITIN-WAF"
local HEADER_CHAITIN_WAF_REASON = "X-APISIX-CHAITIN-WAF-REASON"
local HEADER_CHAITIN_WAF_ERROR = "X-APISIX-CHAITIN-WAF-ERROR"
local HEADER_CHAITIN_WAF_TIME = "X-APISIX-CHAITIN-WAF-TIME"
local HEADER_CHAITIN_WAF_STATUS = "X-APISIX-CHAITIN-WAF-STATUS"
local HEADER_CHAITIN_WAF_ACTION = "X-APISIX-CHAITIN-WAF-ACTION"

local cjson = require "cjson.safe".new()

local function release_checker()
    if not global_healthcheck.checker then
        return
    end

    core.log.info("try to release checker: ", tostring(global_healthcheck.checker))
    global_healthcheck.checker:clear()
    global_healthcheck.checker:stop()
end

local function get_health_checker(metadata)
    if not metadata.checks then
        release_checker()
        return nil
    end

    if global_healthcheck.checker and global_healthcheck.checker_nodes == metadata.nodes then
        return global_healthcheck.checker
    end

    local checker, err = healthcheck.new({
        name = "chaitin-waf-healthcheck",
        -- We can reuse existing shared memory
        shm_name = "upstream-healthcheck",
        checks = metadata.checks,
    })

    release_checker()

    core.log.info("create new health checker for chaitin-waf: ", tostring(checker))

    local host = metadata.checks and metadata.checks.active and metadata.checks.active.host
    local port = metadata.checks and metadata.checks.active and metadata.checks.active.port

    local host_hdr = "127.0.0.1"
    for _, node in ipairs(metadata.nodes) do
        local ok, err = checker:add_target(node.host, port or node.port, host, true, host_hdr)
        if not ok then
            core.log.error("failed to add new health check target: ", node.host, ":", port or node.port, " err: ", err)
        end
    end

    global_healthcheck.checker = checker
    global_healthcheck.checker_nodes = metadata.nodes
    global_healthcheck.status_ver = checker.status_ver

    return checker
end

local function get_healthy_chaitin_server(metadata, checker)
    local nodes = metadata.nodes
    local new_nodes = core.table.new(0, #nodes)
    if not checker then
        for i = 1, #nodes do
            local host, port = nodes[i].host, nodes[i].port
            new_nodes[host .. ":" .. tostring(port)] = 1
        end
        return new_nodes
    end

    local host = metadata.checks and metadata.checks.active and metadata.checks.active.host
    local port = metadata.checks and metadata.checks.active and metadata.checks.active.port
    for _, node in ipairs(nodes) do

        core.log.error("testing chaitin servers: ", node.host, ":", port or node.port, ", host: ", host)
        local ok, err = checker:get_target_status(node.host, port or node.port, host)
        if ok then
            core.log.error("get chaitin-waf health check target status, addr: ",
                    node.host, ":", port or node.port, ", host: ", host, ", err: ", err)
            new_nodes[node.host .. ":" .. tostring(node.port)] = 1
        elseif err then
            core.log.error("failed to get chaitin-waf health check target status, addr: ", node.host, ":", port or node.port, ", host: ", host, ", err: ", err)
        else
            core.log.error("failed to get chaitin-waf health check target status, addr: ", node.host, ":", port or node.port, ", host: ", host)
        end
    end

    return new_nodes
end

local ERR_NO_METADATA = 1
local ERR_NO_HEALTHY_NODES = 2
local ERR_INVALID_MATCH_EXPR = 3

local function get_chaitin_server(ctx)
    local metadata = plugin.plugin_metadata(plugin_name)
    if not core.table.try_read_attr(metadata, "value", "nodes") then
        return nil, nil, { code = ERR_NO_METADATA, message = "chaitin-waf: missing metadata" }
    end

    local checker = get_health_checker(metadata.value)
    if not global_server_picker or global_server_picker.upstream ~= metadata.value.nodes or
            (checker and checker.status_ver ~= global_healthcheck.status_ver) then

        local up_nodes = get_healthy_chaitin_server(metadata.value, checker)
        if core.table.nkeys(up_nodes) == 0 then
            return nil, nil, { code = ERR_NO_HEALTHY_NODES, message = "chaitin-waf: no healthy nodes" }
        end
        core.log.info("healthy chaitin-waf nodes: ", core.json.delay_encode(up_nodes))

        global_server_picker = rr_balancer.new(up_nodes, metadata.value.nodes)
        global_healthcheck.status_ver = checker and checker.status_ver
    end

    local server = global_server_picker.get(ctx)
    local host, port, err = core.utils.parse_addr(server)
    if err then
        return nil, nil, err
    end
    return host, port, nil
end

local function get_server_from_metadata(metadata)
    -- TODO: healthcheck

    return metadata.nodes[1].host, metadata.nodes[1].port
end

local function get_upstream_addr(conf)
    local upstream = conf.upstream
    local servers = upstream.servers -- TODO: 多个 servers 怎么处理？？

    return servers[1]
end

local function check_match(conf, ctx)
    core.log.error("CHECKING conf: ", cjson.encode(conf))
    core.log.error("CHECKING matches: ", cjson.encode(conf.match))
    local match_passed = true

    for _, match in ipairs(conf.match) do
        core.log.error("CHECKING match: " .. tostring(match))
        local expr, err = expr.new(match.vars)
        if err then
            local msg = "failed to create match expression " .. tostring(match.vars) .. ", err: " .. tostring(err)
            core.log.error(msg)
            return { result = false, code = ERR_INVALID_MATCH_EXPR, message = msg }
        end

        match_passed = expr:eval(ctx.var)
        if match_passed then
            core.log.error("EXPR match: " .. tostring(ctx.var))
            break
        end
    end

    return { result = match_passed }
end

function _M.access(conf, ctx)
    local extra_headers = {}
    --[[
        测试 plugin_metadata，包含一个错误的 server
        curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/chaitin-waf -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
       {
          "nodes":[
             {
               "host": "unix:/home/lingsamuel/chaitin-waf/safeline/resources/detector/snserver.sock",
               "port": 8000
             }, {
               "host": "127.0.0.1",
               "port": 1551,
             }
          ]
       }'

        测试 plugin_metadata，包含一个错误的 server
        curl http://127.0.0.1:9180/apisix/admin/plugin_metadata/chaitin-waf -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
        {
            "nodes":[
                {
                    "host": "unix:/home/lingsamuel/chaitin-waf/safeline/resources/detector/snserver.sock",
                    "port": 8000
                },
                {
                    "host": "127.0.0.1",
                    "port": 1551
                }
            ],

            "checks": {
                "active": {
                    "type": "tcp",
                    "host": "localhost",
                    "timeout": 5,
                    "http_path": "/status",
                    "healthy": {
                        "interval": 2,
                        "successes": 1
                    },
                    "unhealthy": {
                        "interval": 1,
                        "http_failures": 2
                    },
                    "req_headers": ["User-Agent: curl/7.29.0"]
                }
            }
        }'

        测试请求：
        curl -H "Host: httpbun.org" http://127.0.0.1:9080/getid=1%20AND%201=1 -i
        curl -H "Host: httpbun.org" http://127.0.0.1:9080/get -i
        curl -H "Host: httpbun.org" -H "release: new_release" http://127.0.0.1:9080/get -i
        curl -H "Host: httpbun.org" -H "release: new_release" http://127.0.0.1:9080/getid=1%20AND%201=1 -i
        测试路由：
        curl http://127.0.0.1:9180/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
       {
           "uri": "/*",
           "plugins": {
               "chaitin-waf": {
                   "upstream": {
                       "servers": ["httpbun.org"]
                   },
                   "match": [
                        {
                            "vars": [
                                ["http_release","==","new_release"]
                            ]
                        }
                    ]
               }
            },
           "upstream": {
               "type": "roundrobin",
               "nodes": {
                   "httpbun.org:80": 1
               }
           }
       }'
    --]]

    local match = check_match(conf, ctx)
    if match and match.message then
        extra_headers[HEADER_CHAITIN_WAF_ERROR] = match.message

        extra_headers[HEADER_CHAITIN_WAF_REASON] = match.message
        core.response.set_header(extra_headers)
        return 500
    elseif not match.result then
        extra_headers[HEADER_CHAITIN_WAF] = "no"
        extra_headers[HEADER_CHAITIN_WAF_REASON] = "no match"
        core.response.set_header(extra_headers)
        return
    end
    extra_headers[HEADER_CHAITIN_WAF_REASON] = "match"

    --local plugin_metadata = plugin.plugin_metadata(plugin_name)
    --get_upstream_addr(conf)
    --
    --local metadata = plugin.plugin_metadata(plugin_name)
    --
    ---- TODO: condition
    --
    --if not core.table.try_read_attr(metadata, "value", "nodes") then
    --    --extra_headers[HEADER_CHAITIN_WAF] = "no"
    --    --core.response.set_header(extra_headers)
    --    --return 503, { message = "Missing metadata for chaitin-waf" }
    --end

    local host, port, err = get_chaitin_server(ctx)
    if err and err.code then
        ngx.log(ngx.ERR, "HEALTHY CHAITIN SERVER: host: " .. err.message)
        extra_headers["X-APISIX-CHAITIN-WAF-SERVER"] = "no-healthy"

        core.response.set_header(extra_headers)
        return
    end
    ngx.log(ngx.ERR, "HEALTHY CHAITIN SERVER: host: " .. tostring(host) .. ", port: " .. tostring(port) .. ", err: " .. tostring(err))
    if err then
        return
    end

    extra_headers["X-APISIX-CHAITIN-WAF-SERVER"] = host
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
        host = host, -- required, SafeLine WAF detection service host, unix domain socket, IP, or domain is supported, string
        port = port, -- required when the host is an IP or domain, SafeLine WAF detection service port, integer
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
    if result and result.status then
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
