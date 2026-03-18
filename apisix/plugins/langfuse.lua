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

local bp_manager_mod  = require("apisix.utils.batch-processor-manager")
local plugin_mod      = require("apisix.plugin")
local core            = require("apisix.core")
local http            = require("resty.http")
local url             = require("net.url")
local uuid            = require("resty.jit-uuid")
local ngx             = ngx
local ngx_now         = ngx.now
local ngx_encode_base64 = ngx.encode_base64
local ipairs          = ipairs
local pairs           = pairs
local type            = type
local math            = math
local pcall           = pcall
local tonumber        = tonumber
local next            = next
local tostring        = tostring
local string          = string
local os              = os

local plugin_name = "langfuse"
local batch_processor_manager = bp_manager_mod.new("langfuse logger")

local metadata_schema = {
    type = "object",
    properties = {
        langfuse_host = {
            type = "string",
            default = "https://cloud.langfuse.com",
        },
        langfuse_public_key = {type = "string"},
        langfuse_secret_key = {type = "string"},
        ssl_verify = {type = "boolean", default = true},
        timeout = {type = "integer", minimum = 1, default = 3},
        detect_ai_requests = {
            type = "boolean",
            default = true,
            description = "Only trace AI API requests"
        },
        ai_endpoints = {
            type = "array",
            items = {type = "string"},
            default = {
                "/chat/completions", "/completions", "/generate",
                "/responses", "/embeddings", "/messages",
            },
            description = "AI endpoint patterns to detect"
        },
    },
    required = {"langfuse_public_key", "langfuse_secret_key"},
}

local schema = {
    type = "object",
    properties = {
        include_metadata = {
            type = "boolean",
            default = true,
            description = "Include request metadata (headers, route info)"
        },
    },
}


local _M = {
    version = 0.1,
    priority = 398,
    name = plugin_name,
    schema = batch_processor_manager:wrap_schema(schema),
    metadata_schema = metadata_schema,
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end
    return core.schema.check(schema, conf)
end


local function get_plugin_attr()
    local metadata = plugin_mod.plugin_metadata(plugin_name)
    if not metadata then
        return nil
    end
    return metadata.value
end


-- Inline response parser functions

local function extract_content(resp_body)
    if type(resp_body) ~= "table" then
        return nil
    end
    local choices = resp_body.choices
    if type(choices) == "table" and #choices > 0 then
        local first = choices[1]
        if type(first) == "table" and type(first.message) == "table" then
            return first.message.content
        end
    end
    return nil
end


local function extract_usage(resp_body)
    if type(resp_body) ~= "table" then
        return nil
    end
    local usage = resp_body.usage
    if type(usage) ~= "table" then
        return nil
    end
    return {
        prompt_tokens = usage.prompt_tokens or 0,
        completion_tokens = usage.completion_tokens or 0,
        total_tokens = usage.total_tokens
            or ((usage.prompt_tokens or 0) + (usage.completion_tokens or 0)),
    }
end


local function extract_model(resp_body)
    if type(resp_body) == "table" then
        return resp_body.model
    end
    return nil
end


local function extract_finish_reason(resp_body)
    if type(resp_body) ~= "table" then
        return nil
    end
    local choices = resp_body.choices
    if type(choices) == "table" and #choices > 0 then
        local first = choices[1]
        if type(first) == "table" then
            return first.finish_reason
        end
    end
    return nil
end


local function extract_input(req_body)
    if type(req_body) ~= "table" then
        return req_body
    end
    return req_body.messages or req_body.prompt or req_body.input or req_body
end


-- Helper functions

local function is_ai_request(plugin_attr, ctx)
    if not plugin_attr.detect_ai_requests then
        return true
    end

    local uri = ctx.var.uri
    local ai_endpoints = plugin_attr.ai_endpoints or {}
    for _, endpoint in ipairs(ai_endpoints) do
        if core.string.has_suffix(uri, endpoint) then
            return true
        end
    end

    return false
end


local function is_embedding_request(uri)
    return core.string.has_suffix(uri, "/embeddings")
end


local function get_iso8601_timestamp(time)
    time = time or ngx_now()
    local seconds = math.floor(time)
    local milliseconds = math.floor((time - seconds) * 1000)
    return string.format("%s.%03dZ", os.date("!%Y-%m-%dT%H:%M:%S", seconds), milliseconds)
end


-- W3C traceparent format: 00-{trace_id}-{span_id}-{flags}
local function parse_traceparent(traceparent)
    if not traceparent then
        return nil, nil
    end

    local version, trace_id, parent_span_id =
        traceparent:match("^(%x%x)%-(%x+)%-(%x+)%-%x%x$")

    if version == "00" and trace_id and parent_span_id then
        return trace_id, parent_span_id
    end

    return nil, nil
end


local function generate_traceparent(trace_id, span_id)
    return string.format("00-%s-%s-01", trace_id, span_id)
end


local function get_generation_level(status)
    if status and status >= 400 then
        return "ERROR"
    end
    return "DEFAULT"
end


-- Token usage priority: ctx.ai_token_usage > ctx.var > resp_body.usage
local function extract_token_usage(ctx, resp_body)
    if ctx.ai_token_usage then
        local usage = ctx.ai_token_usage
        local raw_usage = ctx.llm_raw_usage or {}
        return {
            prompt_tokens = usage.prompt_tokens,
            completion_tokens = usage.completion_tokens,
            total_tokens = usage.total_tokens or
                ((usage.prompt_tokens or 0) + (usage.completion_tokens or 0)),
            cache_creation_input_tokens = raw_usage.cache_creation_input_tokens,
            cache_read_input_tokens = raw_usage.cache_read_input_tokens,
        }
    end

    local prompt_tokens = ctx.var and tonumber(ctx.var.llm_prompt_tokens)
    local completion_tokens = ctx.var and tonumber(ctx.var.llm_completion_tokens)
    if prompt_tokens or completion_tokens then
        return {
            prompt_tokens = prompt_tokens or 0,
            completion_tokens = completion_tokens or 0,
            total_tokens = (prompt_tokens or 0) + (completion_tokens or 0),
        }
    end

    return extract_usage(resp_body)
end


-- Completion content priority: ctx.var.llm_response_text > resp_body
local function extract_completion_content(ctx, resp_body)
    if ctx.var and ctx.var.llm_response_text then
        return ctx.var.llm_response_text
    end
    return extract_content(resp_body)
end


local function get_body_data(ctx)
    local req_body = ctx.langfuse_req_body
    local resp_body = ctx.langfuse_resp_body

    if req_body then
        local ok, req_json = pcall(core.json.decode, req_body)
        if ok then
            req_body = req_json
        end
    end

    if resp_body then
        local ok, resp_json = pcall(core.json.decode, resp_body)
        if ok then
            resp_body = resp_json
        end
    end

    return req_body, resp_body
end


local function create_langfuse_batch(conf, ctx, req_body, resp_body)
    local var = ctx.var
    local start_time = ctx.langfuse_start_time or ngx_now()
    local end_time = ngx_now()
    local latency = math.floor((end_time - start_time) * 1000)
    local status = ngx.status

    local incoming_traceparent = core.request.header(ctx, "traceparent")
    local trace_id, parent_span_id = parse_traceparent(incoming_traceparent)

    -- Use pre-generated IDs from rewrite phase, fall back to new ones
    if not trace_id then
        trace_id = ctx.langfuse_trace_id or uuid.generate_v4()
    end

    local generation_id = ctx.langfuse_generation_id or uuid.generate_v4()
    local timestamp = get_iso8601_timestamp()

    local batch = {}

    local is_streaming = var.request_type == "ai_stream"
    local is_embedding = is_embedding_request(var.uri)

    -- Model priority: ctx.var.llm_model > req_body.model > resp_body.model
    local model = var.llm_model
    if not model and type(req_body) == "table" then
        model = req_body.model
    end
    if not model then
        model = extract_model(resp_body)
    end

    local raw_ttft = var.llm_time_to_first_token
    local time_to_first_token = (raw_ttft and raw_ttft ~= "" and raw_ttft ~= "0")
        and tonumber(raw_ttft) or nil

    local completion_start_time
    if time_to_first_token then
        local completion_start_epoch = start_time + (time_to_first_token / 1000)
        completion_start_time = get_iso8601_timestamp(completion_start_epoch)
    end

    local trace_name, generation_name
    if is_embedding then
        trace_name = model or "embedding"
        generation_name = model or "Embedding"
    else
        trace_name = model or (var.method .. " " .. var.uri)
        generation_name = model or "LLM Generation"
    end

    local trace_output = is_embedding and nil or extract_completion_content(ctx, resp_body)

    local trace_body = {
        id = trace_id,
        name = trace_name,
        userId = core.request.header(ctx, "X-User-Id"),
        sessionId = core.request.header(ctx, "X-Session-Id"),
        model = model or "unknown",
        timestamp = timestamp,
        input = extract_input(req_body),
        output = trace_output,
        tags = {"apisix"},
        metadata = {},
        public = false,
    }

    -- Append additional tags from X-Langfuse-Tags header
    local tags_header = core.request.header(ctx, "X-Langfuse-Tags")
    if tags_header then
        for tag in tags_header:gmatch("[^,]+") do
            core.table.insert(trace_body.tags, tag:match("^%s*(.-)%s*$"))
        end
    end

    -- Build comprehensive metadata
    if conf.include_metadata then
        trace_body.metadata = {
            http_method = var.method,
            http_uri = var.uri,
            http_status = status,
            latency_ms = latency,
            streaming = is_streaming,
            time_to_first_token_ms = time_to_first_token,
            route_id = ctx.route_id,
            route_name = ctx.route_name,
            service_id = ctx.service_id,
            service_name = ctx.service_name,
            consumer = ctx.consumer and ctx.consumer.username,
            user_agent = var.http_user_agent,
            remote_addr = var.remote_addr,
            provider = (ctx.picked_ai_instance and ctx.picked_ai_instance.provider)
                       or (model and model:match("^([^%-/]+)")) or "unknown",
        }

        if incoming_traceparent then
            trace_body.metadata.traceparent = incoming_traceparent
            trace_body.metadata.parent_span_id = parent_span_id
        end

        -- Add custom metadata from header (JSON)
        local custom_metadata = core.request.header(ctx, "X-Langfuse-Metadata")
        if custom_metadata then
            local ok, meta = pcall(core.json.decode, custom_metadata)
            if ok and type(meta) == "table" then
                for k, v in pairs(meta) do
                    trace_body.metadata[k] = v
                end
            end
        end
    end

    core.table.insert(batch, {
        id = trace_id,
        type = "trace-create",
        timestamp = timestamp,
        body = trace_body,
    })

    -- Generation output
    local generation_output
    if is_embedding then
        generation_output = nil
    elseif is_streaming and ctx.llm_stream_response then
        generation_output = ctx.llm_stream_response
    else
        generation_output = resp_body
    end

    local generation_body = {
        id = generation_id,
        traceId = trace_id,
        parentObservationId = parent_span_id,
        name = generation_name,
        startTime = get_iso8601_timestamp(start_time),
        completionStartTime = completion_start_time,
        endTime = get_iso8601_timestamp(end_time),
        input = req_body,
        output = generation_output,
        level = get_generation_level(status),
        statusMessage = status >= 400 and ("HTTP " .. status) or nil,
        model = model,
        metadata = {},
    }

    if type(req_body) == "table" then
        local params = {}
        if req_body.temperature then params.temperature = req_body.temperature end
        if req_body.max_tokens then params.max_tokens = req_body.max_tokens end
        if req_body.top_p then params.top_p = req_body.top_p end
        if req_body.top_k then params.top_k = req_body.top_k end
        if req_body.frequency_penalty then
            params.frequency_penalty = req_body.frequency_penalty
        end
        if req_body.presence_penalty then
            params.presence_penalty = req_body.presence_penalty
        end
        if req_body.stop then params.stop = req_body.stop end
        if req_body.stream then params.stream = req_body.stream end
        if req_body.seed then params.seed = req_body.seed end

        if next(params) then
            generation_body.modelParameters = params
        end
    end

    local token_usage = extract_token_usage(ctx, resp_body)
    if token_usage then
        generation_body.usage = {
            input = token_usage.prompt_tokens,
            output = token_usage.completion_tokens,
            total = token_usage.total_tokens,
            unit = "TOKENS",
        }

        if token_usage.cache_creation_input_tokens
            or token_usage.cache_read_input_tokens then
            generation_body.usage.inputDetails = {
                cache_creation = token_usage.cache_creation_input_tokens,
                cache_read = token_usage.cache_read_input_tokens,
            }
        end

        if token_usage.completion_tokens and latency > 0 then
            generation_body.metadata.completion_tokens_per_second =
                math.floor(token_usage.completion_tokens / (latency / 1000))
        end
    end

    generation_body.metadata.latency_ms = latency
    generation_body.metadata.streaming = is_streaming
    generation_body.metadata.call_type = is_embedding and "embedding" or "completion"
    if time_to_first_token then
        generation_body.metadata.time_to_first_token_ms = time_to_first_token
    end
    if type(resp_body) == "table" then
        generation_body.metadata.response_id = resp_body.id
        generation_body.metadata.system_fingerprint = resp_body.system_fingerprint
        generation_body.metadata.finish_reason = extract_finish_reason(resp_body)
    end

    core.table.insert(batch, {
        id = generation_id,
        type = "generation-create",
        timestamp = timestamp,
        body = generation_body,
    })

    return batch
end


local function send_langfuse_data(plugin_attr, log_message)
    local ingestion_url = plugin_attr.langfuse_host .. "/api/public/ingestion"
    local url_decoded = url.parse(ingestion_url)
    local host = url_decoded.host
    local port = url_decoded.port

    core.log.info("sending langfuse batch to ", ingestion_url)

    if ((not port) and url_decoded.scheme == "https") then
        port = 443
    elseif not port then
        port = 80
    end

    local httpc = http.new()
    httpc:set_timeout(plugin_attr.timeout * 1000)
    local ok, err = httpc:connect(host, port)

    if not ok then
        return false, "failed to connect to host[" .. host .. "] port["
            .. tostring(port) .. "] " .. err
    end

    if url_decoded.scheme == "https" then
        ok, err = httpc:ssl_handshake(true, host, plugin_attr.ssl_verify)
        if not ok then
            return false, "failed to perform SSL with host[" .. host .. "] "
                .. "port[" .. tostring(port) .. "] " .. err
        end
    end

    local auth = "Basic " .. ngx_encode_base64(
        plugin_attr.langfuse_public_key .. ":" .. plugin_attr.langfuse_secret_key)

    local httpc_res, httpc_err = httpc:request({
        method = "POST",
        path = url_decoded.path,
        body = log_message,
        headers = {
            ["Host"] = host,
            ["Content-Type"] = "application/json",
            ["Authorization"] = auth,
        }
    })

    if not httpc_res then
        return false, "error while sending data to [" .. host .. "] port["
            .. tostring(port) .. "] " .. httpc_err
    end

    if httpc_res.status >= 400 then
        local resp_body = httpc_res:read_body()
        return false, "server returned status code[" .. httpc_res.status .. "] host["
            .. host .. "] port[" .. tostring(port) .. "] "
            .. "body[" .. (resp_body or "") .. "]"
    end

    -- Read body and return connection to keepalive pool
    httpc_res:read_body()
    httpc:set_keepalive()

    return true
end


function _M.rewrite(conf, ctx)
    local plugin_attr = get_plugin_attr()
    if not plugin_attr then
        core.log.warn("langfuse: plugin_metadata is required, skipping")
        return
    end

    if not is_ai_request(plugin_attr, ctx) then
        return
    end

    ctx.langfuse_start_time = ngx_now()

    -- Pre-generate trace_id and generation_id for header_filter
    local incoming_traceparent = core.request.header(ctx, "traceparent")
    local trace_id = parse_traceparent(incoming_traceparent)

    if not trace_id then
        local request_id = core.request.header(ctx, "X-Request-Id")
        if request_id then
            trace_id = request_id
        else
            trace_id = uuid.generate_v4()
        end
    end

    local generation_id = uuid.generate_v4()
    ctx.langfuse_trace_id = trace_id
    ctx.langfuse_generation_id = generation_id
    ctx.langfuse_traceparent = generate_traceparent(trace_id, generation_id)

    local req_body = core.request.get_body()
    if req_body then
        ctx.langfuse_req_body = req_body
    end
end


function _M.header_filter(conf, ctx)
    if ctx.langfuse_traceparent then
        core.response.set_header("traceparent", ctx.langfuse_traceparent)
    end
end


function _M.body_filter(conf, ctx)
    if not ctx.langfuse_start_time then
        return
    end

    local chunk = ngx.arg[1]
    if chunk and chunk ~= "" then
        local chunks = ngx.ctx.langfuse_resp_chunks
        if not chunks then
            chunks = {}
            ngx.ctx.langfuse_resp_chunks = chunks
        end
        core.table.insert(chunks, chunk)
    end

    if ngx.arg[2] then  -- eof
        local chunks = ngx.ctx.langfuse_resp_chunks
        if chunks then
            ctx.langfuse_resp_body = core.table.concat(chunks, "")
        end
    end
end


function _M.log(conf, ctx)
    local plugin_attr = get_plugin_attr()
    if not plugin_attr then
        return
    end

    if not is_ai_request(plugin_attr, ctx) then
        return
    end

    local req_body, resp_body = get_body_data(ctx)

    local batch = create_langfuse_batch(conf, ctx, req_body, resp_body)

    if batch_processor_manager:add_entry(conf, batch) then
        return
    end

    local func = function(entries, batch_max_size)
        -- entries is [[trace, gen], [trace, gen], ...]
        -- Flatten into a single batch array
        local flat_batch = {}
        for _, entry in ipairs(entries) do
            if type(entry) == "table" and entry.type then
                -- single batch item
                core.table.insert(flat_batch, entry)
            else
                -- array of batch items
                for _, item in ipairs(entry) do
                    core.table.insert(flat_batch, item)
                end
            end
        end

        local data, err = core.json.encode({batch = flat_batch})
        if not data then
            return false, "error occurred while encoding the data: " .. err
        end

        return send_langfuse_data(plugin_attr, data)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, batch, ctx, func)
end


return _M
