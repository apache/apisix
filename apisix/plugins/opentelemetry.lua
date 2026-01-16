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
            type = "object",
            description = "configuration for plugin execution tracing",
            properties = {
                enabled = {
                    type = "boolean",
                    description = "whether to trace individual plugin execution",
                    default = false
                },
                plugin_span_kind = {
                    type = "string",
                    enum = {"internal", "server"},
                    description = "span kind for plugin execution spans. "
                               .. "Some observability providers may exclude internal "
                               .. "spans from metrics and dashboards. Use 'server' "
                               .. "if you need plugin spans included in "
                               .. "service-level metrics.",
                    default = "internal"
                },
                excluded_plugins = {
                    type = "array",
                    description = "plugins to exclude from tracing "
                               .. "(e.g., opentelemetry, prometheus)",
                    items = {
                        type = "string",
                        minLength = 1,
                    },
                    default = {"opentelemetry", "prometheus"}
                }
            },
            default = {
                enabled = false,
                plugin_span_kind = "internal",
                excluded_plugins = {"opentelemetry", "prometheus"}
            }
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


-- Plugin span management functions
-- =================================

-- Build a consistent key for identifying a plugin phase span
local function build_plugin_phase_key(plugin_name, phase)
    return plugin_name .. ":" .. phase
end

-- Create phase span
local function create_phase_span(api_ctx, plugin_name, phase)
    if not api_ctx.otel then
        return nil
    end

    if not api_ctx.otel_plugin_spans then
        api_ctx.otel_plugin_spans = {}
    end

    -- Create unique key for plugin+phase combination
    local span_key = build_plugin_phase_key(plugin_name, phase)
    if not api_ctx.otel_plugin_spans[span_key] then
        -- Create span named "plugin_name phase" directly under main request span
        local phase_span_ctx = api_ctx.otel.start_span({
            name = plugin_name .. " " .. phase,
            kind = api_ctx.otel_plugin_span_kind,
            attributes = {
                attr.string("apisix.plugin_name", plugin_name),
                attr.string("apisix.plugin_phase", phase),
            }
        })

        api_ctx.otel_plugin_spans[span_key] = phase_span_ctx
        -- Store current plugin context for child spans
        api_ctx._current_plugin_phase = span_key
    end

    return api_ctx.otel_plugin_spans[span_key]
end

-- Finish phase span
local function finish_phase_span(api_ctx, plugin_name, phase, error_msg)
    if not api_ctx.otel_plugin_spans then
        return
    end

    local span_key = build_plugin_phase_key(plugin_name, phase)
    local phase_span_ctx = api_ctx.otel_plugin_spans[span_key]

    if phase_span_ctx then
        api_ctx.otel.stop_span(phase_span_ctx, error_msg)
        api_ctx.otel_plugin_spans[span_key] = nil

        -- Clear current plugin phase context when span is finished
        if api_ctx._current_plugin_phase == span_key then
            api_ctx._current_plugin_phase = nil
        end
    end
end

-- Cleanup all plugin spans
local function cleanup_plugin_spans(api_ctx)
    if not api_ctx.otel_plugin_spans then
        return
    end

    for span_key, phase_span_ctx in pairs(api_ctx.otel_plugin_spans) do
        if phase_span_ctx then
            api_ctx.otel.stop_span(phase_span_ctx)
        end
    end

    api_ctx.otel_plugin_spans = nil
    api_ctx._current_plugin_phase = nil
end


-- OpenTelemetry API for plugins
-- =============================

-- No-op API when tracing is disabled
local noop_api = setmetatable({
    with_span = function(span_info, fn)
        if not fn then
            return nil, "with_span: function is required"
        end
        -- Execute function without tracing, passing nil as span_ctx (no actual span)
        local result = {pcall(fn or function() end, nil)}
        -- Return unpacked results (starting from index 2 to preserve error-first pattern)
        return unpack(result, 2)
    end
}, {
    __index = function(_, _)
        return function() return nil end
    end
})

-- Create simple OpenTelemetry API for plugins
local function create_otel_api(api_ctx, tracer, main_context)
    -- Initialize span stack for tracking current spans
    if not api_ctx._otel_span_stack then
        api_ctx._otel_span_stack = {}
    end

    local api = {
        start_span = function(span_info)
            if not (span_info and span_info.name) then
                return nil
            end

            -- Get parent context (prioritize explicit parent, then current phase span, then main)
            local current_phase_span = api_ctx._current_plugin_phase and
                api_ctx.otel_plugin_spans and
                api_ctx.otel_plugin_spans[api_ctx._current_plugin_phase]

            local parent_context = span_info.parent or current_phase_span or main_context

            -- Use the provided kind directly (users should pass span_kind constants)
            local span_kind_value = span_info.kind or span_kind.internal
            local attributes = span_info.attributes or {}
            local span_ctx = tracer:start(parent_context, span_info.name, {
                kind = span_kind_value,
                attributes = attributes,
            })

            -- Track this span as current (push to stack)
            core.table.insert(api_ctx._otel_span_stack, span_ctx)

            return span_ctx
        end,

        stop_span = function(span_ctx, error_msg)
            if not span_ctx then
                return
            end

            local span = span_ctx:span()
            if not span then
                return
            end

            if error_msg then
                span:set_status(span_status.ERROR, error_msg)
            end

            span:finish()

            -- Remove from stack if it's the current span (pop from stack)
            if api_ctx._otel_span_stack and
               #api_ctx._otel_span_stack > 0 and
               api_ctx._otel_span_stack[#api_ctx._otel_span_stack] == span_ctx then
                core.table.remove(api_ctx._otel_span_stack)
            end
        end,

        current_span = function()
            -- Return the most recently started span (top of stack)
            if api_ctx._otel_span_stack and #api_ctx._otel_span_stack > 0 then
                return api_ctx._otel_span_stack[#api_ctx._otel_span_stack]
            end
            return nil
        end,

        get_plugin_context = function(plugin_name, phase)
            if not (api_ctx.otel_plugin_spans and phase) then
                return nil
            end
            return api_ctx.otel_plugin_spans[build_plugin_phase_key(plugin_name, phase)]
        end,
    }

    function api.with_span(span_info, fn)
        if not fn then
            return nil, "with_span: the function parameter is required"
        end

        -- Start the span (this applies the initial attributes)
        local span_ctx = api.start_span(span_info)

        -- Execute function with pcall for error protection, passing span_ctx to callback
        local result = {pcall(fn, span_ctx)}

        -- Handle results:
        -- - If pcall fails: result[1] = false, result[2] = Lua error
        -- - If function succeeds: result[1] = true, result[2] = err (from fn), result[3+] = values
        local pcall_success, error_msg = result[1], result[2]

        -- Determine the actual error to report:
        -- - If pcall failed, use the Lua error
        -- - If pcall succeeded but function returned an error, use the function error
        -- - Otherwise, no error
        local final_error = nil
        if not pcall_success then
            -- pcall failed - Lua error occurred
            final_error = error_msg
        elseif error_msg ~= nil then
            -- pcall succeeded but function returned an error
            final_error = error_msg
        end

        if span_ctx then
            -- Stop span with error message if there was an error
            api.stop_span(span_ctx, final_error)
        end

        -- Return unpacked results (starting from index 2 to preserve error-first pattern)
        -- This returns: err, ...values
        return unpack(result, 2)
    end

    return api
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
    if conf.trace_plugins.enabled then
        -- Map string span kind to span_kind constant
        local kind_mapping = {
            internal = span_kind.internal,
            server = span_kind.server,
        }
        api_ctx.otel_plugin_span_kind = kind_mapping[conf.trace_plugins.plugin_span_kind]

        -- Store excluded plugins configuration
        api_ctx.otel_excluded_plugins = {}
        if conf.trace_plugins.excluded_plugins then
            for _, excluded_name in ipairs(conf.trace_plugins.excluded_plugins) do
                api_ctx.otel_excluded_plugins[excluded_name] = true
            end
        end

        -- Create OpenTelemetry API for plugins
        api_ctx.otel = create_otel_api(api_ctx, tracer, ctx)
    else
        -- Always provide API - no-op when tracing disabled
        api_ctx.otel = noop_api
    end

    -- inject trace context into the headers of upstream HTTP request
    trace_context_propagator:inject(ctx, ngx.req)
end


function _M.before_proxy(conf, api_ctx)
    -- Only add upstream attributes if we have an active trace context
    if not (api_ctx.otel_context_token and api_ctx.picked_server) then return end

    if not (context:current() and context:current():span()) then return end

    -- Build upstream host information from picked_server
    local server = api_ctx.picked_server
    local upstream_addr = string_format("%s:%s", server.host, server.port)
    local upstream_host = server.upstream_host or server.host

    -- Add upstream attributes to the main span
    local upstream_attributes = {
        attr.string("apisix.upstream.addr", upstream_addr),
        attr.string("apisix.upstream.host", upstream_host),
        attr.string("apisix.upstream.ip", server.host),
        attr.int("apisix.upstream.port", server.port),
    }
    context:current():span():set_attributes(unpack(upstream_attributes))
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

        span:set_attributes(attr.int("http.status_code", upstream_status))
        span:finish()
        -- Clear the context token to prevent double finishing
        api_ctx.otel_context_token = nil

        -- Cleanup plugin spans (guaranteed cleanup on request end)
        cleanup_plugin_spans(api_ctx)
    end
end


-- Public functions for plugin tracing integration
-- ===============================================

-- Start plugin phase span
-- Safe to call even if OpenTelemetry plugin is not enabled (will be no-op)
function _M.start_plugin_span(api_ctx, plugin_name, phase)
    -- Check if plugin tracing is enabled by checking for otel_plugin_span_kind
    -- only set when trace_plugins.enabled is true
    if not api_ctx.otel_plugin_span_kind then
        return nil
    end

    -- Check if plugin is excluded from tracing
    if api_ctx.otel_excluded_plugins and api_ctx.otel_excluded_plugins[plugin_name] then
        return nil
    end

    return create_phase_span(api_ctx, plugin_name, phase)
end


-- Finish plugin phase span
-- Safe to call even if OpenTelemetry plugin is not enabled (will be no-op)
function _M.finish_plugin_span(api_ctx, plugin_name, phase, error_msg)
    -- If tracing disabled, api_ctx.otel_plugin_spans won't be initialized
    if not api_ctx.otel_plugin_spans then
        return
    end

    -- Check if plugin is excluded from tracing
    if api_ctx.otel_excluded_plugins and api_ctx.otel_excluded_plugins[plugin_name] then
        return
    end

    finish_phase_span(api_ctx, plugin_name, phase, error_msg)
end


return _M
