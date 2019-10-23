local core = require("apisix.core")
local new_tracer = require("opentracing.tracer").new
local zipkin_codec = require("apisix.plugins.zipkin.codec")
local new_random_sampler = require("apisix.plugins.zipkin.random_sampler").new
local new_reporter = require("apisix.plugins.zipkin.reporter").new
local ngx = ngx
local pairs = pairs

local plugin_name = "zipkin"


local schema = {
    type = "object",
    properties = {
        endpoint = {type = "string"},
        sample_ratio = {type = "number", minimum = 0.00001, maximum = 1}
    },
    required = {"endpoint", "sample_ratio"}
}


local _M = {
    version = 0.1,
    priority = -1000, -- last running plugin, but before serverless post func
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function create_tracer(conf)
    local tracer = new_tracer(new_reporter(conf), new_random_sampler(conf))
    tracer:register_injector("http_headers", zipkin_codec.new_injector())
    tracer:register_extractor("http_headers", zipkin_codec.new_extractor())
    return tracer
end

local function report2endpoint(premature, reporter)
    if premature then
        return
    end

    local ok, err = reporter:flush()
    if not ok then
        core.log.error("reporter flush ", err)
        return
    end

    core.log.info("report2endpoint ok")
end


function _M.rewrite(conf, ctx)
    local tracer = core.lrucache.plugin_ctx(plugin_name, ctx,
                                            create_tracer, conf)

    ctx.opentracing_sample = tracer.sampler:sample()
    if not ctx.opentracing_sample then
        return
    end

    local wire_context = tracer:extract("http_headers",
                                        core.request.headers(ctx))

    local start_timestamp = ngx.req.start_time()
    local request_span = tracer:start_span("apisix.request", {
        child_of = wire_context,
        start_timestamp = start_timestamp,
        tags = {
            component = "apisix",
            ["span.kind"] = "server",
            ["http.method"] = ctx.var.method,
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
        rewrite_span = nil,
        access_span = nil,
        proxy_span = nil,
    }

    local request_span = ctx.opentracing.request_span
    ctx.opentracing.rewrite_span = request_span:start_child_span(
                                            "apisix.rewrite", start_timestamp)
    ctx.REWRITE_END_TIME = tracer:time()
    ctx.opentracing.rewrite_span:finish(ctx.REWRITE_END_TIME)
end

function _M.access(conf, ctx)
    if not ctx.opentracing_sample then
        return
    end

    local opentracing = ctx.opentracing

    opentracing.access_span = opentracing.request_span:start_child_span(
            "apisix.access", ctx.REWRITE_END_TIME)

    local tracer = opentracing.tracer

    ctx.ACCESS_END_TIME = tracer:time()
    opentracing.access_span:finish(ctx.ACCESS_END_TIME)

    opentracing.proxy_span = opentracing.request_span:start_child_span(
            "apisix.proxy", ctx.ACCESS_END_TIME)

    -- send headers to upstream
    local outgoing_headers = {}
    tracer:inject(opentracing.proxy_span, "http_headers", outgoing_headers)
    for k, v in pairs(outgoing_headers) do
        core.response.set_header(k, v)
    end
end


function _M.header_filter(conf, ctx)
    if not ctx.opentracing_sample then
        return
    end

    local opentracing = ctx.opentracing

    ctx.HEADER_FILTER_END_TIME = opentracing.tracer:time()
    opentracing.body_filter_span = opentracing.proxy_span:start_child_span(
            "apisix.body_filter", ctx.HEADER_FILTER_END_TIME)
end


function _M.log(conf, ctx)
    if not ctx.opentracing_sample then
        return
    end

    local opentracing = ctx.opentracing

    local log_end_time = opentracing.tracer:time()
    opentracing.body_filter_span:finish(log_end_time)

    local upstream_status = core.response.get_upstream_status(ctx)
    opentracing.request_span:set_tag("http.status_code", upstream_status)
    opentracing.proxy_span:finish(log_end_time)
    opentracing.request_span:finish(log_end_time)

    local reporter = opentracing.tracer.reporter
    local ok, err = ngx.timer.at(0, report2endpoint, reporter)
    if not ok then
        core.log.error("failed to create timer: ", err)
    end
end

return _M
