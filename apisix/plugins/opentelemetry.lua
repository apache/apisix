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
local string_format = string.format

local lrucache = core.lrucache.new({
    type = 'plugin', count = 128, ttl = 24 * 60 * 60,
})

local asterisk = string.byte("*", 1)

local metadata_schema = {
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
        set_ngx_var = {
          type = "boolean",
          description = "set nginx variables",
          default = false,
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
        },
        trace_plugins = {
            type = "boolean",
            description = "whether to trace individual plugin execution",
            default = false
        },
        plugin_span_kind = {
            type = "string",
            enum = {"internal", "server"},
            description = "span kind for plugin execution spans. "
                       .. "Some observability providers may exclude internal spans from metrics "
                       .. "and dashboards. Use 'server' if you need plugin spans included in "
                       .. "service-level metrics.",
            default = "internal"
        }
    }
}


local _M = {
    version = 0.1,
    priority = 12009,
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        local ok, err = core.schema.check(metadata_schema, conf)
        if not ok then
            return ok, err
        end
        local check = {"collector.address"}
        core.utils.check_https(check, conf, plugin_name)
        return true
    end
    return core.schema.check(schema, conf)
end


local hostname
local sampler_factory

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
end


local function create_tracer_obj(conf, plugin_info)
    if plugin_info.trace_id_source == "x-request-id" then
        id_generator.new_ids = function()
            local trace_id = core.request.headers()["x-request-id"] or ngx_var.request_id
            return trace_id, id_generator.new_span_id()
        end
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


-- Plugin tracing helper functions
local function create_plugin_span(tracer, plugin_name, phase, parent_context, api_ctx)
    -- Use a more descriptive span name that includes the plugin and phase
    local span_name = string_format("plugin.%s.%s", plugin_name, phase)
    local attributes = {
        attr.string("apisix.plugin.name", plugin_name),
        attr.string("apisix.plugin.phase", phase),
        attr.string("apisix.plugin.operation", "execute"),
        -- Set resource name to distinguish plugin spans from main spans
        attr.string("resource.name", span_name)
    }

    -- Add request context attributes if available
    if api_ctx and api_ctx.var then
        local vars = api_ctx.var
        table.insert(attributes, attr.string("http.method", vars.method or "unknown"))
        table.insert(attributes, attr.string("http.target", vars.request_uri or "unknown"))
        table.insert(attributes, attr.string("net.host.name", vars.host or "unknown"))
        table.insert(attributes, attr.string("http.user_agent", vars.http_user_agent or "unknown"))

        -- Add route information if available
        if api_ctx.route_id then
            table.insert(attributes, attr.string("apisix.route_id", api_ctx.route_id))
        end
        if api_ctx.route_name then
            table.insert(attributes, attr.string("apisix.route_name", api_ctx.route_name))
        end
        if api_ctx.curr_req_matched and api_ctx.curr_req_matched._path then
            table.insert(attributes, attr.string("http.route", api_ctx.curr_req_matched._path))
        end

        -- Add service information if available
        if api_ctx.service_id then
            table.insert(attributes, attr.string("apisix.service_id", api_ctx.service_id))
        end
        if api_ctx.service_name then
            table.insert(attributes, attr.string("apisix.service_name", api_ctx.service_name))
        end
    end

    -- Get the configured span kind or default to internal
    local kind = span_kind.internal
    if api_ctx.otel_plugin_span_kind then
        kind = api_ctx.otel_plugin_span_kind
    end

    -- Create child span with proper parent context
    local ctx = tracer:start(parent_context, span_name, {
        kind = kind,
        attributes = attributes,
    })

    return ctx
end


local function finish_plugin_span(plugin_span_ctx, success, error_msg)
    if not plugin_span_ctx then
        return
    end

    local span = plugin_span_ctx:span()
    if not span then
        return
    end

    if not success then
        span:set_status(span_status.ERROR, error_msg or "plugin execution failed")
    end

    span:finish()
end


-- Store plugin spans in api_ctx for cleanup
local function store_plugin_span(api_ctx, plugin_name, phase, span_ctx)
    if not api_ctx.otel_plugin_spans then
        api_ctx.otel_plugin_spans = {}
    end

    -- Use nested structure to avoid key collisions
    if not api_ctx.otel_plugin_spans[plugin_name] then
        api_ctx.otel_plugin_spans[plugin_name] = {}
    end
    api_ctx.otel_plugin_spans[plugin_name][phase] = {
        span_ctx = span_ctx,
        finished = false
    }
end


local function cleanup_plugin_spans(api_ctx)
    if not api_ctx.otel_plugin_spans then
        return
    end

    for plugin_name, phases in pairs(api_ctx.otel_plugin_spans) do
        if phases then
            for phase, span_data in pairs(phases) do
                if span_data and not span_data.finished and span_data.span_ctx then
                    local span = span_data.span_ctx:span()
                    if span then
                        span:finish()
                    end
                end
            end
        end
    end

    api_ctx.otel_plugin_spans = nil
end


function _M.rewrite(conf, api_ctx)
    local metadata = plugin.plugin_metadata(plugin_name)
    if metadata == nil then
        core.log.warn("plugin_metadata is required for opentelemetry plugin to working properly")
        return
    end
    core.log.info("metadata: ", core.json.delay_encode(metadata))
    local plugin_info = metadata.value
    local vars = api_ctx.var

    local tracer, err = core.lrucache.plugin_ctx(lrucache, api_ctx, nil,
                                                create_tracer_obj, conf, plugin_info)
    if not tracer then
        core.log.error("failed to fetch tracer object: ", err)
        return
    end

    local span_name = string_format("http.%s", vars.method)

    local attributes = {
        attr.string("net.host.name", vars.host),
        attr.string("http.method", vars.method),
        attr.string("http.scheme", vars.scheme),
        attr.string("http.target", vars.request_uri),
        attr.string("http.user_agent", vars.http_user_agent),
    }

    if api_ctx.curr_req_matched then
        table.insert(attributes, attr.string("apisix.route_id", api_ctx.route_id))
        table.insert(attributes, attr.string("apisix.route_name", api_ctx.route_name))
        table.insert(attributes, attr.string("http.route", api_ctx.curr_req_matched._path))
        span_name = string_format("http.%s %s", vars.method, api_ctx.curr_req_matched._path)
    end

    if api_ctx.service_id then
        table.insert(attributes, attr.string("apisix.service_id", api_ctx.service_id))
        table.insert(attributes, attr.string("apisix.service_name", api_ctx.service_name))
    end

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

    -- extract trace context from the headers of downstream HTTP request
    local upstream_context = trace_context_propagator:extract(context, ngx.req)

    local ctx = tracer:start(upstream_context, span_name, {
        kind = span_kind.server,
        attributes = attributes,
    })

    if plugin_info.set_ngx_var then
      local span_context = ctx:span():context()
      ngx_var.opentelemetry_context_traceparent = string_format("00-%s-%s-%02x",
                                                                 span_context.trace_id,
                                                                 span_context.span_id,
                                                                 span_context.trace_flags)
      ngx_var.opentelemetry_trace_id = span_context.trace_id
      ngx_var.opentelemetry_span_id = span_context.span_id
    end

    api_ctx.otel_context_token = ctx:attach()

    -- Store tracer and configuration for plugin tracing
    if conf.trace_plugins then
        api_ctx.otel_tracer = tracer
        api_ctx.otel_main_context = ctx
        api_ctx.otel_trace_plugins = true

        -- Map string span kind to span_kind constant
        local kind_mapping = {
            internal = span_kind.internal,
            server = span_kind.server,
        }
        local span_kind_value = conf.plugin_span_kind or "internal"
        api_ctx.otel_plugin_span_kind = kind_mapping[span_kind_value] or span_kind.internal

        -- Note: We don't create a span for the OpenTelemetry plugin itself to avoid recursion
    end

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

        span:set_attributes(attr.int("http.status_code", upstream_status))

        span:finish()

        -- Finish OpenTelemetry plugin span if it exists
        if api_ctx.otel_trace_plugins then
            _M.finish_plugin_span(api_ctx, "opentelemetry", "rewrite", true, nil)
        end

        -- Cleanup plugin spans
        cleanup_plugin_spans(api_ctx)
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

        -- Cleanup plugin spans (guaranteed cleanup on request end)
        cleanup_plugin_spans(api_ctx)
    end
end


-- Public functions for plugin tracing integration
function _M.start_plugin_span(api_ctx, plugin_name, phase)
    if not api_ctx.otel_trace_plugins or not api_ctx.otel_tracer then
        return nil
    end

    -- Prevent recursion: don't trace the OpenTelemetry plugin itself
    if plugin_name == "opentelemetry" then
        return nil
    end

    -- Always use the stored main context to ensure proper parent-child relationship
    local parent_ctx = api_ctx.otel_main_context
    if not parent_ctx then
        return nil
    end

    local plugin_span_ctx = create_plugin_span(api_ctx.otel_tracer, plugin_name, phase, parent_ctx,
                                              api_ctx)
    store_plugin_span(api_ctx, plugin_name, phase, plugin_span_ctx)

    return plugin_span_ctx
end


function _M.finish_plugin_span(api_ctx, plugin_name, phase, success, error_msg)
    if not api_ctx.otel_trace_plugins or not api_ctx.otel_plugin_spans then
        return
    end

    -- Prevent recursion: don't trace the OpenTelemetry plugin itself
    if plugin_name == "opentelemetry" then
        return
    end

    local plugin_data = api_ctx.otel_plugin_spans[plugin_name]
    if not plugin_data then
        return
    end

    local span_data = plugin_data[phase]
    if not span_data or span_data.finished then
        return
    end

    finish_plugin_span(span_data.span_ctx, success, error_msg)
    span_data.finished = true
end


return _M
