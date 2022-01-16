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

local context_storage = require("opentelemetry.context_storage")
local context = require("opentelemetry.context").new(context_storage)
local carrier_new = require("opentelemetry.trace.propagation.carrier").new
local trace_context = require("opentelemetry.trace.propagation.trace_context")

local ngx_var = ngx.var
local ngx_req = ngx.req

local hostname

local attr_schema = {
    type = "object",
    properties = {
        x_request_id_as_trace_id = {
            type = "boolean",
            description = "use x-request-id as new trace id",
            default = false,
        },
        resource = {
            type = "object",
            description = "additional resource",
            additional_properties = {{type = "boolean"}, {type = "number"}, {type = "string"}},
        },
        collector = {
            type = "object",
            description = "otel collector",
            properties = {
                address = {type = "string", description = "host:port", default = "127.0.0.1:4317"},
                request_timeout = {type = "integer", description = "second uint", default = 3},
                request_headers = {
                    type = "object",
                    description = "http headers",
                    additional_properties = {
                        one_of = {{type = "boolean"},{type = "number"}, {type = "string"}},
                   },
                }
            },
            default = {address = "127.0.0.1:4317", request_timeout = 3}
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
        tags = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    position = {
                        type = "string",
                        enum = {"http", "arg", "cookie"}
                    },
                    name = {
                        type = "string", minLength = 1
                    }
                }
            }
        }
    }
}

local _M = {
    version = 0.1,
    priority = -1200, -- last running plugin, but before serverless post func
    name = plugin_name,
    schema = schema,
    attr_schema = attr_schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

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

    if plugin_info.x_request_id_as_trace_id then
        id_generator.new_ids = function()
            local trace_id = ngx_req.get_headers()["x-request-id"] or ngx_var.request_id
            return trace_id, id_generator.new_span_id()
        end
    end
end

local tracers = {}

local function fetch_tracer(conf, ctx)
    local t = tracers[ctx.route_id]
    if t and t.v == ctx.conf_version then
        return t.tracer
    end

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
    local tracer = tp:tracer("opentelemetry-lua")
    tracers[ctx.route_id] = {tracer = tracer, v = ctx.conf_version}

    return tracer
end

function _M.access(conf, api_ctx)
    -- extract trace context from the headers of downstream HTTP request
    local upstream_context = trace_context.extract(context, carrier_new())
    local attributes = {
        attr.string("service", api_ctx.service_name),
        attr.string("route", api_ctx.route_name),
    }
    if conf.tags then
        for _, tag in ipairs(conf.tags) do
            local key = tag.position .. "_" .. tag.name
            local val = api_ctx.var[key]
            if val then
                core.table.insert(attributes, attr.string(key, val))
            end
        end
    end

    local ctx, _ = fetch_tracer(conf, api_ctx):start(upstream_context, api_ctx.var.request_uri, {
        kind = span_kind.client,
        attributes = attributes,
    })
    ctx:attach()

    -- inject trace context into the headers of upstream HTTP request
    trace_context.inject(ctx, carrier_new())
end

function _M.body_filter(conf, ctx)
    if ngx.arg[2] then
        local upstream_status = core.response.get_upstream_status(ctx)
        -- get span from current context
        local span = context:current():span()
        if upstream_status and upstream_status >= 500 then
            span:set_status(span_status.error,
                            "upstream response status: " .. tostring(upstream_status))
        end

        span:finish()
    end
end

function _M.destroy()
    if process.type() ~= "worker" then
        return
    end

    for _, t in pairs(tracers) do
        t.tracer.provider:shutdown()
    end
end

return _M
