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
local plugin_name = "opentelemetry"
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local process = require("ngx.process")

local always_off_sampler_new = require("opentelemetry.trace.sampling.always_off_sampler").new
local always_on_sampler_new = require("opentelemetry.trace.sampling.always_on_sampler").new
local parent_base_sampler_new = require("opentelemetry.trace.sampling.parent_base_sampler").new
local trace_id_ratio_sampler_new =
                                require("opentelemetry.trace.sampling.trace_id_ratio_sampler").new

local exporter_client_new = require("opentelemetry.trace.exporter.http_client").new
local otlp_exporter_new = require("opentelemetry.trace.exporter.otlp").new
local batch_span_processor_new = require("opentelemetry.trace.batch_span_processor").new
local id_generator = require("opentelemetry.trace.id_generator")
local tracer_provider_new = require("opentelemetry.trace.tracer_provider").new

local span_kind = require("opentelemetry.trace.span_kind")
local span_status = require("opentelemetry.trace.span_status")
local resource_new = require("opentelemetry.resource").new
local attr = require("opentelemetry.attribute")

local context = require("opentelemetry.context").new()
local trace_context_propagator =
                require("opentelemetry.trace.propagation.text_map.trace_context_propagator").new()

local ngx     = ngx
local ngx_var = ngx.var
local table   = table
local type    = type
local pairs   = pairs
local ipairs  = ipairs
local unpack  = unpack

local lrucache = core.lrucache.new({
    type = 'plugin', count = 128, ttl = 24 * 60 * 60,
})

local asterisk = string.byte("*", 1)

local attr_schema = {
    type = "object",
    properties = {
        trace_id_source = {
            type = "string",
            enum = {"x-request-id", "random"},
            description = "the source of trace id",
            default = "random",
        },
        resource = {
            type = "object",
            description = "additional resource",
            additionalProperties = {{type = "boolean"}, {type = "number"}, {type = "string"}},
        },
        collector = {
            type = "object",
            description = "opentelemetry collector",
            properties = {
                address = {type = "string", description = "host:port", default = "127.0.0.1:4318"},
                request_timeout = {type = "integer", description = "second uint", default = 3},
                request_headers = {
                    type = "object",
                    description = "http headers",
                    additionalProperties = {
                        one_of = {{type = "boolean"},{type = "number"}, {type = "string"}},
                   },
                }
            },
            default = {address = "127.0.0.1:4318", request_timeout = 3}
        },
        batch_span_processor = {
            type = "object",
            description = "batch span processor",
            properties = {
                drop_on_queue_full = {
                    type = "boolean",
                    description = "if true, drop span when queue is full,"
                            .. " otherwise force process batches",
                },
                max_queue_size = {
                    type = "integer",
                    description = "maximum queue size to buffer spans for delayed processing",
                },
                batch_timeout = {
                    type = "number",
                    description = "maximum duration for constructing a batch",
                },
                inactive_timeout = {
                    type = "number",
                    description = "maximum duration for processing batches",
                },
                max_export_batch_size = {
                    type = "integer",
                    description = "maximum number of spans to process in a single batch",
                }
            },
            default = {},
        },
    },
}

local schema = {
    type = "object",
    properties = {
        sampler = {
            type = "object",
            properties = {
                name = {
                    type = "string",
                    enum = {"always_on", "always_off", "trace_id_ratio", "parent_base"},
                    title = "sampling strategy",
                    default = "always_off"
                },
                options = {
                    type = "object",
                    properties = {
                        fraction = {
                            type = "number", title = "trace_id_ratio fraction", default = 0
                        },
                        root = {
                            type = "object",
                            title = "parent_base root sampler",
                            properties = {
                                name = {
                                    type = "string",
                                    enum = {"always_on", "always_off", "trace_id_ratio"},
                                    title = "sampling strategy",
                                    default = "always_off"
                                },
                                options = {
                                    type = "object",
                                    properties = {
                                        fraction = {
                                            type = "number",
                                            title = "trace_id_ratio fraction parameter",
                                            default = 0,
                                        },
                                    },
                                    default = {fraction = 0}
                                }
                            },
                            default = {name = "always_off", options = {fraction = 0}}
                        },
                    },
                    default = {fraction = 0, root = {name = "always_off"}}
                }
            },
            default = {name = "always_off", options = {fraction = 0, root = {name = "always_off"}}}
        },
        additional_attributes = {
            type = "array",
            items = {
                type = "string",
                minLength = 1,
            }
        },
        additional_header_prefix_attributes = {
            type = "array",
            items = {
                type = "string",
                minLength = 1,
            }
        }
    }
}


local _M = {
    version = 0.1,
    priority = 12009,
    name = plugin_name,
    schema = schema,
    attr_schema = attr_schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local hostname
local sampler_factory
local plugin_info

function _M.init()
    if process.type() ~= "worker" then
        return
    end

    sampler_factory = {
        always_off = always_off_sampler_new,
        always_on = always_on_sampler_new,
        parent_base = parent_base_sampler_new,
        trace_id_ratio = trace_id_ratio_sampler_new,
    }
    hostname = core.utils.gethostname()

    plugin_info = plugin.plugin_attr(plugin_name) or {}
    local ok, err = core.schema.check(attr_schema, plugin_info)
    if not ok then
        core.log.error("failed to check the plugin_attr[", plugin_name, "]",
                ": ", err)
        return
    end

    if plugin_info.trace_id_source == "x-request-id" then
        id_generator.new_ids = function()
            local trace_id = core.request.headers()["x-request-id"] or ngx_var.request_id
            return trace_id, id_generator.new_span_id()
        end
    end
end


local function create_tracer_obj(conf)
    -- create exporter
    local exporter = otlp_exporter_new(exporter_client_new(plugin_info.collector.address,
                                                            plugin_info.collector.request_timeout,
                                                            plugin_info.collector.request_headers))
    -- create span processor
    local batch_span_processor = batch_span_processor_new(exporter,
                                                            plugin_info.batch_span_processor)
    -- create sampler
    local sampler
    local sampler_name = conf.sampler.name
    local sampler_options = conf.sampler.options
    if sampler_name == "parent_base" then
        local root_sampler
        if sampler_options.root then
            local name, fraction = sampler_options.root.name, sampler_options.root.options.fraction
            root_sampler = sampler_factory[name](fraction)
        else
            root_sampler = always_off_sampler_new()
        end
        sampler = sampler_factory[sampler_name](root_sampler)
    else
        sampler = sampler_factory[sampler_name](sampler_options.fraction)
    end
    local resource_attrs = {attr.string("hostname", hostname)}
    if plugin_info.resource then
        if not plugin_info.resource["service.name"] then
            table.insert(resource_attrs, attr.string("service.name", "APISIX"))
        end
        for k, v in pairs(plugin_info.resource) do
            if type(v) == "string" then
                table.insert(resource_attrs, attr.string(k, v))
            end
            if type(v) == "number" then
                table.insert(resource_attrs, attr.double(k, v))
            end
            if type(v) == "boolean" then
                table.insert(resource_attrs, attr.bool(k, v))
            end
        end
    end
    -- create tracer provider
    local tp = tracer_provider_new(batch_span_processor, {
        resource = resource_new(unpack(resource_attrs)),
        sampler = sampler,
    })
    -- create tracer
    return tp:tracer("opentelemetry-lua")
end


local function inject_attributes(attributes, wanted_attributes, source, with_prefix)
    for _, key in ipairs(wanted_attributes) do
        local is_key_a_match = #key >= 2 and key:byte(-1) == asterisk and with_prefix

        if is_key_a_match then
            local prefix = key:sub(0, -2)
            for possible_key, value in pairs(source) do
                if core.string.has_prefix(possible_key, prefix) then
                    core.table.insert(attributes, attr.string(possible_key, value))
                end
            end
        else
            local val = source[key]
            if val then
                core.table.insert(attributes, attr.string(key, val))
            end
        end
    end
end


function _M.rewrite(conf, api_ctx)
    local tracer, err = core.lrucache.plugin_ctx(lrucache, api_ctx, nil, create_tracer_obj, conf)
    if not tracer then
        core.log.error("failed to fetch tracer object: ", err)
        return
    end

    -- extract trace context from the headers of downstream HTTP request
    local upstream_context = trace_context_propagator:extract(context, ngx.req)
    local attributes = {
        attr.string("service", api_ctx.service_name),
        attr.string("route", api_ctx.route_name),
    }

    if conf.additional_attributes then
        inject_attributes(attributes, conf.additional_attributes, api_ctx.var, false)
    end

    if conf.additional_header_prefix_attributes then
        inject_attributes(
            attributes,
            conf.additional_header_prefix_attributes,
            core.request.headers(api_ctx),
            true
        )
    end

    local ctx = tracer:start(upstream_context, api_ctx.var.request_uri, {
        kind = span_kind.server,
        attributes = attributes,
    })
    api_ctx.otel_context_token = ctx:attach()

    -- inject trace context into the headers of upstream HTTP request
    trace_context_propagator:inject(ctx, ngx.req)
end


function _M.delayed_body_filter(conf, api_ctx)
    if api_ctx.otel_context_token and ngx.arg[2] then
        local ctx = context:current()
        ctx:detach(api_ctx.otel_context_token)
        api_ctx.otel_context_token = nil

        -- get span from current context
        local span = ctx:span()
        local upstream_status = core.response.get_upstream_status(api_ctx)
        if upstream_status and upstream_status >= 500 then
            span:set_status(span_status.ERROR,
                            "upstream response status: " .. upstream_status)
        end

        span:finish()
    end
end


-- body_filter maybe not called because of empty http body response
-- so we need to check if the span has finished in log phase
function _M.log(conf, api_ctx)
    if api_ctx.otel_context_token then
        -- ctx:detach() is not necessary, because of ctx is stored in ngx.ctx
        local upstream_status = core.response.get_upstream_status(api_ctx)

        -- get span from current context
        local span = context:current():span()
        if upstream_status and upstream_status >= 500 then
            span:set_status(span_status.ERROR,
                    "upstream response status: " .. upstream_status)
        end

        span:finish()
    end
end


return _M
