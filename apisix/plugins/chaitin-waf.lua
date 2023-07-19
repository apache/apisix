local require = require
local core = require("apisix.core")
local http = require("resty.http")
local rr_balancer = require("apisix.balancer.roundrobin")
local plugin = require("apisix.plugin")
local healthcheck = require("resty.healthcheck")
local t1k = require "resty.t1k"
local expr = require("resty.expr.v1")

local ngx = ngx
local ngx_now = ngx.now
local string = string
local fmt = string.format
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
        add_header = {
            type = "boolean",
            default = true
        },
        add_debug_header = {
            type = "boolean",
            default = false
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

    if not checker then
        core.log.error("fail to create healthcheck instance: ", err)
        return nil
    end

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

local function get_chaitin_server(metadata, ctx)
    local checker = get_health_checker(metadata.value)
    if not global_server_picker or global_server_picker.upstream ~= metadata.value.nodes or
            (checker and checker.status_ver ~= global_healthcheck.status_ver) then

        local up_nodes = get_healthy_chaitin_server(metadata.value, checker)
        if core.table.nkeys(up_nodes) == 0 then
            return nil, nil, "no healthy nodes"
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

local function get_upstream_addr(conf)
    local upstream = conf.upstream
    local servers = upstream.servers -- TODO: 多个 servers 怎么处理？？

    return servers[1]
end

local function check_match(conf, ctx)
    local match_passed = true

    for _, match in ipairs(conf.match) do
        local exp, err = expr.new(match.vars)
        if err then
            local msg = "failed to create match expression for " .. tostring(match.vars) .. ", err: " .. tostring(err)
            core.log.error(msg)
            return false, msg
        end

        match_passed = exp:eval(ctx.var)
        if match_passed then
            break
        end
    end

    return match_passed, nil
end

local HEADER_CHAITIN_WAF = "X-APISIX-CHAITIN-WAF"
local HEADER_CHAITIN_WAF_ERROR = "X-APISIX-CHAITIN-WAF-ERROR"
local HEADER_CHAITIN_WAF_TIME = "X-APISIX-CHAITIN-WAF-TIME"
local HEADER_CHAITIN_WAF_STATUS = "X-APISIX-CHAITIN-WAF-STATUS"
local HEADER_CHAITIN_WAF_ACTION = "X-APISIX-CHAITIN-WAF-ACTION"
local HEADER_CHAITIN_WAF_SERVER = "X-APISIX-CHAITIN-WAF-SERVER"
local blocked_message = [[{"code": %s, "success":false, "message": "blocked by Chaitin SafeLine Web Application Firewall", "event_id": "%s"}]]

local function do_access(conf, ctx)
    local extra_headers = {}

    local match, err = check_match(conf, ctx)
    if not match then
        if err then
            extra_headers[HEADER_CHAITIN_WAF] = "err"
            extra_headers[HEADER_CHAITIN_WAF_ERROR] = tostring(err)
            return 500, nil, extra_headers
        else
            extra_headers[HEADER_CHAITIN_WAF] = "no"
            return nil, nil, extra_headers
        end
    end

    local metadata = plugin.plugin_metadata(plugin_name)
    if not core.table.try_read_attr(metadata, "value", "nodes") then
        extra_headers[HEADER_CHAITIN_WAF] = "err"
        extra_headers[HEADER_CHAITIN_WAF_ERROR] = "missing metadata"
        return 500, nil, extra_headers
    end

    local host, port, err = get_chaitin_server(metadata, ctx)
    if err then
        extra_headers[HEADER_CHAITIN_WAF] = "unhealthy"
        extra_headers[HEADER_CHAITIN_WAF_ERROR] = tostring(err)

        return 500, nil, extra_headers
    end

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
        remote_addr = remote_addr, -- remote address from ngx.var.VARIABLE, string, default from ngx.var.remote_addr
    }

    extra_headers[HEADER_CHAITIN_WAF_SERVER] = host
    extra_headers[HEADER_CHAITIN_WAF] = "yes"

    local start_time = ngx_now() * 1000
    local ok, err, result = t1k.do_access(t, false)
    if not ok then
        extra_headers[HEADER_CHAITIN_WAF] = "waf-err"
        extra_headers[HEADER_CHAITIN_WAF_ERROR] = tostring(err)
    else
        extra_headers[HEADER_CHAITIN_WAF_ACTION] = "pass"
    end
    extra_headers[HEADER_CHAITIN_WAF_TIME] = ngx_now() * 1000 - start_time

    local code = 200
    if result then
        code = result.status
        if result.status then
            extra_headers[HEADER_CHAITIN_WAF_STATUS] = code
            extra_headers[HEADER_CHAITIN_WAF_ACTION] = "reject"

            return tonumber(code), fmt(blocked_message, code, result.event_id), extra_headers
        end
    end
    extra_headers[HEADER_CHAITIN_WAF_STATUS] = code

    return nil, nil, extra_headers
end

function _M.access(conf, ctx)
    local code, msg, extra_headers = do_access(conf, ctx)

    if not conf.add_debug_header then
        extra_headers[HEADER_CHAITIN_WAF_ERROR] = nil
        extra_headers[HEADER_CHAITIN_WAF_SERVER] = nil
    end
    if conf.add_header then
        core.response.set_header(extra_headers)
    end

    return code, msg

    -- TODO: blacklist/whitelist?
    -- TODO: captcha?
    -- TODO: 请求体过大，支持截断，例如上传文件
end

function _M.header_filter(conf, ctx)
    t1k.do_header_filter()
end

function _M.body_filter(conf, ctx)
end

return _M
