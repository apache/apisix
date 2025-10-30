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
local plugin = require("apisix.plugin")
local expr = require("resty.expr.v1")
local content_decode = require("apisix.utils.content-decode")
local ngx = ngx
local pairs = pairs
local ngx_now = ngx.now
local ngx_header = ngx.header
local os_date = os.date
local str_byte = string.byte
local str_sub  = string.sub
local math_floor = math.floor
local ngx_update_time = ngx.update_time
local req_get_body_data = ngx.req.get_body_data
local is_http = ngx.config.subsystem == "http"
local req_get_body_file = ngx.req.get_body_file
local MAX_REQ_BODY      = 524288      -- 512 KiB
local MAX_RESP_BODY     = 524288      -- 512 KiB
local io                = io

local lru_log_format = core.lrucache.new({
    ttl = 300, count = 512
})

local _M = {}


local function get_request_body(max_bytes)
    local req_body = req_get_body_data()
    if req_body then
        if max_bytes and #req_body >= max_bytes then
            req_body = str_sub(req_body, 1, max_bytes)
        end
        return req_body
    end

    local file_name = req_get_body_file()
    if not file_name then
        return nil
    end

    core.log.info("attempt to read body from file: ", file_name)

    local f, err = io.open(file_name, 'r')
    if not f then
        return nil, "fail to open file " .. err
    end

    req_body = f:read(max_bytes)
    f:close()

    return req_body
end


local function gen_log_format(format)
    local log_format = {}
    for k, var_name in pairs(format) do
        if var_name:byte(1, 1) == str_byte("$") then
            log_format[k] = {true, var_name:sub(2)}
        else
            log_format[k] = {false, var_name}
        end
    end
    core.log.info("log_format: ", core.json.delay_encode(log_format))
    return log_format
end

local log_vars = {
    latency = function() return (ngx_now() - ngx.req.start_time()) * 1000 end,
    upstream_latency = function(ctx)
        return ctx.var.upstream_response_time and ctx.var.upstream_response_time * 1000 or nil
    end,
    apisix_latency = function(ctx)
        local latency = (ngx_now() - ngx.req.start_time()) * 1000
        local upstream_latency =
            ctx.var.upstream_response_time and ctx.var.upstream_response_time * 1000 or 0
        local apisix_latency = latency - upstream_latency
        -- The latency might be negative, as Nginx uses different time measurements in
        -- different metrics.
        -- See https://github.com/apache/apisix/issues/5146#issuecomment-928919399
        if apisix_latency < 0 then apisix_latency = 0 end
        return apisix_latency
    end,
    client_ip = function(ctx) return core.request.get_remote_client_ip(ctx) end,
    start_time = function() return ngx.req.start_time() * 1000 end,
    hostname = function() return core.utils.gethostname() end,
    version = function() return core.version.VERSION end,
    request_method = function() return ngx.req.get_method() end,
    request_headers = function() return ngx.req.get_headers() end,
    request_querystring = function() return ngx.req.get_uri_args() end,
    request_body = function(ctx, max_req_body_bytes)
        local max_bytes = max_req_body_bytes or MAX_REQ_BODY
        local req_body, err = get_request_body(max_bytes)
        if err then
            core.log.error("fail to get request body: ", err)
            return nil
        end
        return req_body
    end,
    response_status = function() return ngx.status end,
    response_headers = function() return ngx.resp.get_headers() end,
    response_size = function(ctx) return ctx.var.bytes_sent end,
    response_body = function (ctx) return ctx.resp_body end,
    upstream = function(ctx) return ctx.var.upstream_addr end,
    url = function(ctx)
        local var = ctx.var
        return string.format("%s://%s:%s%s",
            var.scheme,
            var.host,
            var.server_port,
            var.request_uri)
    end,
    consumer_username = function(ctx)
        return ctx.consumer and ctx.consumer.username or nil
    end,
    service_id = function(ctx)
        local matched_route = ctx.matched_route and ctx.matched_route.value
        return matched_route and matched_route.service_id
    end,
    route_id = function(ctx)
        local matched_route = ctx.matched_route and ctx.matched_route.value
        return matched_route and matched_route.id
    end,
}

local function get_custom_format_log(ctx, format, max_req_body_bytes)
    local log_format = lru_log_format(format or "", nil, gen_log_format, format)
    local entry = core.table.new(0, core.table.nkeys(log_format))
    for k, var_attr in pairs(log_format) do
        if var_attr[1] then
            local key = var_attr[2]
            if log_vars[key] then
                entry[k] = log_vars[key](ctx, max_req_body_bytes)
            else
                entry[k] = ctx.var[key]
            end
        else
            entry[k] = var_attr[2]
        end
    end

    local matched_route = ctx.matched_route and ctx.matched_route.value
    if matched_route then
        entry.service_id = matched_route.service_id
        entry.route_id = matched_route.id
    end
    return entry
end
-- export the log getter so we can mock in tests
_M.get_custom_format_log = get_custom_format_log


-- for test
function _M.inject_get_custom_format_log(f)
    get_custom_format_log = f
    _M.get_custom_format_log = f
end


local function latency_details_in_ms(ctx)
    local latency = (ngx_now() - ngx.req.start_time()) * 1000
    local upstream_latency, apisix_latency = nil, latency

    if ctx.var.upstream_response_time then
        upstream_latency = ctx.var.upstream_response_time * 1000
        apisix_latency = apisix_latency - upstream_latency

        -- The latency might be negative, as Nginx uses different time measurements in
        -- different metrics.
        -- See https://github.com/apache/apisix/issues/5146#issuecomment-928919399
        if apisix_latency < 0 then
            apisix_latency = 0
        end
    end

    return latency, upstream_latency, apisix_latency
end
_M.latency_details_in_ms = latency_details_in_ms


local function get_full_log(ngx, conf)
    local ctx = ngx.ctx.api_ctx
    local var = ctx.var

    local consumer
    if ctx.consumer then
        consumer = {
            username = log_vars.consumer_username(ctx),
            group_id = ctx.consumer.group_id
        }
    end

    local log = {
        request = {
            url = log_vars.url(ctx),
            uri = var.request_uri,
            method = log_vars.request_method(),
            headers = log_vars.request_headers(),
            querystring = log_vars.request_querystring(),
            size = var.request_length
        },
        response = {
            status = log_vars.response_status(),
            headers = log_vars.response_headers(),
            size = log_vars.response_size(ctx)
        },
        server = {
            hostname = log_vars.hostname(),
            version = log_vars.version()
        },
        upstream = log_vars.upstream(ctx),
        service_id = log_vars.service_id(ctx),
        route_id = log_vars.route_id(ctx),
        consumer = consumer,
        client_ip = log_vars.client_ip(ctx),
        start_time = log_vars.start_time(),
        latency = log_vars.latency(),
        upstream_latency = log_vars.upstream_latency(ctx),
        apisix_latency = log_vars.apisix_latency(ctx)
    }

    if conf.include_resp_body then
        log.response.body = log_vars.response_body(ctx)
    end

    if conf.include_req_body then

        local log_request_body = true

        if conf.include_req_body_expr then

            if not conf.request_expr then
                local request_expr, err = expr.new(conf.include_req_body_expr)
                if not request_expr then
                    core.log.error('generate request expr err ' .. err)
                    return log
                end
                conf.request_expr = request_expr
            end

            local result = conf.request_expr:eval(ctx.var)

            if not result then
                log_request_body = false
            end
        end

        if log_request_body then
            log.request.body = log_vars.request_body(ctx, conf.max_req_body_bytes)
        end
    end

    return log
end
_M.get_full_log = get_full_log


-- for test
function _M.inject_get_full_log(f)
    get_full_log = f
    _M.get_full_log = f
end


local function is_match(match, ctx)
    local match_result
    for _, m in pairs(match) do
        local expr, _ = expr.new(m)
        match_result = expr:eval(ctx.var)
        if match_result then
            break
        end
    end

    return match_result
end


function _M.get_log_entry(plugin_name, conf, ctx)
    -- If the "match" configuration is set and the matching conditions are not met,
    -- then do not log the message.
    if conf.match and not is_match(conf.match, ctx) then
        return
    end

    local metadata = plugin.plugin_metadata(plugin_name)
    core.log.info("metadata: ", core.json.delay_encode(metadata))

    local entry
    local customized = false

    local has_meta_log_format = metadata and metadata.value.log_format
        and core.table.nkeys(metadata.value.log_format) > 0

    local format
    if conf.log_format then
        format = conf.log_format
    elseif has_meta_log_format then
        format = metadata.value.log_format
    end

    if format then
        customized = true
        entry = get_custom_format_log(ctx, format, conf.max_req_body_bytes)
    else
        if is_http then
            entry = get_full_log(ngx, conf)
        else
            -- get_full_log doesn't work in stream
            core.log.error(plugin_name, "'s log_format is not set")
        end
    end

    if ctx.llm_summary then
        entry.llm_summary = ctx.llm_summary
    end
    if ctx.llm_request then
        entry.llm_request = ctx.llm_request
    end
    if ctx.llm_response_text then
        entry.llm_response_text = ctx.llm_response_text
    end
    return entry, customized
end


function _M.get_req_original(ctx, conf)
    local data = {
        ctx.var.request, "\r\n"
    }
    for k, v in pairs(ngx.req.get_headers()) do
        core.table.insert_tail(data, k, ": ", v, "\r\n")
    end
    core.table.insert(data, "\r\n")

    if conf.include_req_body then
        local max_req_body_bytes = conf.max_req_body_bytes or MAX_REQ_BODY
        local req_body = get_request_body(max_req_body_bytes)
        core.table.insert(data, req_body)
    end

    return core.table.concat(data, "")
end


function _M.check_log_schema(conf)
    if conf.include_req_body_expr then
        local ok, err = expr.new(conf.include_req_body_expr)
        if not ok then
            return nil, "failed to validate the 'include_req_body_expr' expression: " .. err
        end
    end
    if conf.include_resp_body_expr then
        local ok, err = expr.new(conf.include_resp_body_expr)
        if not ok then
            return nil, "failed to validate the 'include_resp_body_expr' expression: " .. err
        end
    end
    return true, nil
end


function _M.collect_body(conf, ctx)
    if conf.include_resp_body then
        local log_response_body = true

        if conf.include_resp_body_expr then
            if not conf.response_expr then
                local response_expr, err = expr.new(conf.include_resp_body_expr)
                if not response_expr then
                    core.log.error('generate response expr err ' .. err)
                    return
                end
                conf.response_expr = response_expr
            end

            if ctx.res_expr_eval_result == nil then
                ctx.res_expr_eval_result = conf.response_expr:eval(ctx.var)
            end

            if not ctx.res_expr_eval_result then
                log_response_body = false
            end
        end

        if log_response_body then
            local max_resp_body_bytes = conf.max_resp_body_bytes or MAX_RESP_BODY

            if ctx._resp_body_bytes and ctx._resp_body_bytes >= max_resp_body_bytes then
                return
            end
            local final_body = core.response.hold_body_chunk(ctx, true, max_resp_body_bytes)
            if not final_body then
                return
            end

            local response_encoding = ngx_header["Content-Encoding"]
            if not response_encoding then
                ctx.resp_body = final_body
                return
            end

            local decoder = content_decode.dispatch_decoder(response_encoding)
            if not decoder then
                core.log.warn("unsupported compression encoding type: ",
                              response_encoding)
                ctx.resp_body = final_body
                return
            end

            local decoded_body, err = decoder(final_body)
            if err ~= nil then
                core.log.warn("try decode compressed data err: ", err)
                ctx.resp_body = final_body
                return
            end

            ctx.resp_body = decoded_body
        end
    end
end


function _M.get_rfc3339_zulu_timestamp(timestamp)
    ngx_update_time()
    local now = timestamp or ngx_now()
    local second = math_floor(now)
    local millisecond = math_floor((now - second) * 1000)
    return os_date("!%Y-%m-%dT%T.", second) .. core.string.format("%03dZ", millisecond)
end


return _M
