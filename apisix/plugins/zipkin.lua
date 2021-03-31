--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local core = require("apisix.core")
local new_tracer = require("opentracing.tracer").new
local zipkin_codec = require("apisix.plugins.zipkin.codec")
local new_random_sampler = require("apisix.plugins.zipkin.random_sampler").new
local new_reporter = require("apisix.plugins.zipkin.reporter").new
local ngx = ngx
local ngx_re = require("ngx.re")
local pairs = pairs
local tonumber = tonumber

local plugin_name = "zipkin"
local ZIPKIN_SPAN_VER_1 = 1
local ZIPKIN_SPAN_VER_2 = 2


local lrucache = core.lrucache.new({
    type = "plugin",
})

local schema = {
    type = "object",
    properties = {
        endpoint = {type = "string"},
        sample_ratio = {type = "number", minimum = 0.00001, maximum = 1},
        service_name = {
            type = "string",
            description = "service name for zipkin reporter",
            default = "APISIX",
        },
        server_addr = {
            type = "string",
            description = "default is $server_addr, you can specify your external ip address",
            pattern = "^[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}$"
        },
        span_version = {
            enum = {ZIPKIN_SPAN_VER_1, ZIPKIN_SPAN_VER_2},
            default = ZIPKIN_SPAN_VER_2,
        },
    },
    required = {"endpoint", "sample_ratio"}
}


local _M = {
    version = 0.1,
    priority = 11011,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function create_tracer(conf,ctx)
    conf.route_id = ctx.route_id
    local reporter = new_reporter(conf)
    reporter:init_processor()
    local tracer = new_tracer(reporter, new_random_sampler(conf))
    tracer:register_injector("http_headers", zipkin_codec.new_injector())
    tracer:register_extractor("http_headers", zipkin_codec.new_extractor())
    return tracer
end


local function parse_b3(b3)
    -- See https://github.com/openzipkin/b3-propagation#single-header
    if b3 == "0" then
        return nil, nil, nil, "0", nil
    end

    local pieces, err = ngx_re.split(b3, "-", nil, nil, 4)
    if not pieces then
        return err
    end
    if not pieces[1] then
        return "missing trace_id"
    end
    if not pieces[2] then
        return "missing span_id"
    end
    return nil, pieces[1], pieces[2], pieces[3], pieces[4]
end


function _M.rewrite(plugin_conf, ctx)
    local conf = core.table.clone(plugin_conf)
    -- once the server started, server_addr and server_port won't change, so we can cache it.
    conf.server_port = tonumber(ctx.var['server_port'])

    if not conf.server_addr or conf.server_addr == '' then
        conf.server_addr = ctx.var["server_addr"]
    end

    local tracer = core.lrucache.plugin_ctx(lrucache, ctx, conf.server_addr .. conf.server_port,
                                            create_tracer, conf, ctx)

    local headers = core.request.headers(ctx)
    local per_req_sample_ratio

    -- X-B3-Flags: if it equals '1' then it overrides sampling policy
    -- We still want to warn on invalid sampled header, so do this after the above
    local debug = headers["x-b3-flags"]
    if debug == "1" then
        per_req_sample_ratio = 1
    end

    local trace_id, request_span_id, sampled, parent_span_id
    local b3 = headers["b3"]
    if b3 then
        -- don't pass b3 header by default
        core.request.set_header(ctx, "b3", nil)

        local err
        err, trace_id, request_span_id, sampled, parent_span_id = parse_b3(b3)

        if err then
            core.log.error("invalid b3 header: ", b3, ", ignored: ", err)
            return 400
        end

        if sampled == "d" then
            core.request.set_header(ctx, "x-b3-flags", "1")
            sampled = "1"
        end
    else
        -- X-B3-Sampled: if the client decided to sample this request, we do too.
        sampled = headers["x-b3-sampled"]
        trace_id = headers["x-b3-traceid"]
        parent_span_id = headers["x-b3-parentspanid"]
        request_span_id = headers["x-b3-spanid"]
    end

    if sampled == "1" or sampled == "true" then
        per_req_sample_ratio = 1
    elseif sampled == "0" or sampled == "false" then
        per_req_sample_ratio = 0
    end

    ctx.opentracing_sample = tracer.sampler:sample(per_req_sample_ratio or conf.sample_ratio)
    if not ctx.opentracing_sample then
        core.request.set_header(ctx, "x-b3-sampled", "0")
        return
    end

    local zipkin_ctx = core.tablepool.fetch("zipkin_ctx", 0, 3)
    zipkin_ctx.trace_id = trace_id
    zipkin_ctx.parent_span_id = parent_span_id
    zipkin_ctx.request_span_id = request_span_id
    ctx.zipkin = zipkin_ctx

    local wire_context = tracer:extract("http_headers", ctx)

    local start_timestamp = ngx.req.start_time()
    local request_span = tracer:start_span("apisix.request", {
        child_of = wire_context,
        start_timestamp = start_timestamp,
        tags = {
            component = "apisix",
            ["span.kind"] = "server",
            ["http.method"] = ctx.var.request_method,
            ["http.url"] = ctx.var.request_uri,
             -- TODO: support ipv6
            ["peer.ipv4"] = core.request.get_remote_client_ip(ctx),
            ["peer.port"] = core.request.get_remote_client_port(ctx),
        }
    })

    ctx.opentracing = {
        tracer = tracer,
        wire_context = wire_context,
        request_span = request_span,
    }

    local request_span = ctx.opentracing.request_span
    if conf.span_version == ZIPKIN_SPAN_VER_1 then
        ctx.opentracing.rewrite_span = request_span:start_child_span("apisix.rewrite",
                                                                     start_timestamp)

        ctx.REWRITE_END_TIME = tracer:time()
        ctx.opentracing.rewrite_span:finish(ctx.REWRITE_END_TIME)
    else
        ctx.opentracing.proxy_span = request_span:start_child_span("apisix.proxy",
                                                                   start_timestamp)
    end
end

function _M.access(conf, ctx)
    if not ctx.opentracing_sample then
        return
    end

    local opentracing = ctx.opentracing
    local tracer = opentracing.tracer

    if conf.span_version == ZIPKIN_SPAN_VER_1 then
        opentracing.access_span = opentracing.request_span:start_child_span(
            "apisix.access", ctx.REWRITE_END_TIME)

        ctx.ACCESS_END_TIME = tracer:time()
        opentracing.access_span:finish(ctx.ACCESS_END_TIME)

        opentracing.proxy_span = opentracing.request_span:start_child_span(
                "apisix.proxy", ctx.ACCESS_END_TIME)
    end

    -- send headers to upstream
    local outgoing_headers = {}
    tracer:inject(opentracing.proxy_span, "http_headers", outgoing_headers)
    for k, v in pairs(outgoing_headers) do
        core.request.set_header(ctx, k, v)
    end
end


function _M.header_filter(conf, ctx)
    if not ctx.opentracing_sample then
        return
    end

    local opentracing = ctx.opentracing
    local end_time = opentracing.tracer:time()

    if conf.span_version == ZIPKIN_SPAN_VER_1 then
        ctx.HEADER_FILTER_END_TIME = end_time
        if  opentracing.proxy_span then
            opentracing.body_filter_span = opentracing.proxy_span:start_child_span(
                "apisix.body_filter", ctx.HEADER_FILTER_END_TIME)
        end
    else
        opentracing.proxy_span:finish(end_time)
        opentracing.response_span = opentracing.request_span:start_child_span(
            "apisix.response_span", ctx.HEADER_FILTER_END_TIME)
    end
end


function _M.log(conf, ctx)
    if not ctx.opentracing_sample then
        return
    end

    local opentracing = ctx.opentracing

    local log_end_time = opentracing.tracer:time()

    if conf.span_version == ZIPKIN_SPAN_VER_1 then
        if opentracing.body_filter_span then
            opentracing.body_filter_span:finish(log_end_time)
        end
        if opentracing.proxy_span then
            opentracing.proxy_span:finish(log_end_time)
        end

    else
        opentracing.response_span:finish(log_end_time)
    end

    local upstream_status = core.response.get_upstream_status(ctx)
    opentracing.request_span:set_tag("http.status_code", upstream_status)

    opentracing.request_span:finish(log_end_time)

    if ctx.zipkin_ctx then
        core.tablepool.release("zipkin_ctx", ctx.zipkin_ctx)
    end
end

return _M
