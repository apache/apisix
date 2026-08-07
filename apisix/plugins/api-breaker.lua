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
local plugin_name = "api-breaker"
local ngx = ngx
local math = math
local error = error
local ipairs = ipairs


local shared_buffer = ngx.shared["plugin-".. plugin_name]
if not shared_buffer then
    error("failed to get ngx.shared dict when load plugin " .. plugin_name)
end

-- Circuit breaker states (only for ratio policy)
local CLOSED = 0
local OPEN = 1
local HALF_OPEN = 2

-- Number of fixed time buckets used to approximate the sliding window for
-- the ratio policy. Each bucket is keyed by its own epoch, so aging out old
-- data is just a matter of the epoch falling outside the window -- no
-- request ever has to "reset" shared state that another request is
-- concurrently reading or writing.
local NUM_BUCKETS = 10

local schema = {
    type = "object",
    properties = {
        break_response_code = {
            type = "integer",
            minimum = 200,
            maximum = 599,
        },
        break_response_body = {
            type = "string"
        },
        break_response_headers = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    key = {
                        type = "string",
                        minLength = 1
                    },
                    value = {
                        type = "string",
                        minLength = 1
                    }
                },
                required = {"key", "value"},
            }
        },
        max_breaker_sec = {
            type = "integer",
            minimum = 3,
            default = 300,
            description = "Circuit breaker duration in seconds " ..
                         "(applies to both count and ratio policies)"
        },
        policy = {
            type = "string",
            enum = { "unhealthy-count", "unhealthy-ratio" },
            default = "unhealthy-count",
        }
    },
    required = { "break_response_code" },
    ["if"] = {
        properties = {
            policy = {
                enum = { "unhealthy-count" },
            },
        },
    },
    ["then"] = {
        properties = {
            unhealthy = {
                type = "object",
                properties = {
                    http_statuses = {
                        type = "array",
                        minItems = 1,
                        items = {
                            type = "integer",
                            minimum = 500,
                            maximum = 599,
                        },
                        uniqueItems = true,
                        default = { 500 }
                    },
                    failures = {
                        type = "integer",
                        minimum = 1,
                        default = 3,
                    }
                },
                default = { http_statuses = { 500 }, failures = 3 }
            },
            healthy = {
                type = "object",
                properties = {
                    http_statuses = {
                        type = "array",
                        minItems = 1,
                        items = {
                            type = "integer",
                            minimum = 200,
                            maximum = 499,
                        },
                        uniqueItems = true,
                        default = { 200 }
                    },
                    successes = {
                        type = "integer",
                        minimum = 1,
                        default = 3,
                    }
                },
                default = { http_statuses = { 200 }, successes = 3 }
            }
        }
    },
    ["else"] = {
        ["if"] = {
            properties = {
                policy = {
                    enum = { "unhealthy-ratio" },
                },
            },
        },
        ["then"] = {
            properties = {
                unhealthy = {
                    type = "object",
                    properties = {
                        http_statuses = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "integer",
                                minimum = 500,
                                maximum = 599,
                            },
                            uniqueItems = true,
                            default = { 500 }
                        },
                        error_ratio = {
                            type = "number",
                            minimum = 0,
                            maximum = 1,
                            default = 0.5,
                            description = "Failure rate threshold to trigger circuit breaker"
                        },
                        min_request_threshold = {
                            type = "integer",
                            minimum = 1,
                            default = 10,
                            description = "Minimum number of calls before " ..
                                         "circuit breaker can be triggered"
                        },
                        sliding_window_size = {
                            type = "integer",
                            minimum = 10,
                            maximum = 3600,
                            default = 300,
                            description = "Size of the sliding window in seconds"
                        },
                        half_open_max_calls = {
                            type = "integer",
                            minimum = 1,
                            maximum = 20,
                            default = 3,
                            description = "Number of permitted calls when " ..
                                         "circuit breaker is half-open"
                        }
                    },
                    default = {
                        http_statuses = { 500 },
                        error_ratio = 0.5,
                        min_request_threshold = 10,
                        sliding_window_size = 300,
                        half_open_max_calls = 3
                    }
                },
                healthy = {
                    type = "object",
                    properties = {
                        http_statuses = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "integer",
                                minimum = 200,
                                maximum = 499,
                            },
                            uniqueItems = true,
                            default = { 200 }
                        },
                        success_ratio = {
                            type = "number",
                            minimum = 0,
                            maximum = 1,
                            default = 0.6,
                            description = "Success rate threshold to close circuit breaker " ..
                                         "from half-open state"
                        }
                    },
                    default = { http_statuses = { 200 }, success_ratio = 0.6 }
                }
            }
        }
    }
}

-- Key generation functions (based on latest APISIX version)
local function gen_healthy_key(ctx)
    return "healthy-" .. core.request.get_host(ctx) .. ctx.var.uri
end

local function gen_unhealthy_key(ctx)
    return "unhealthy-" .. core.request.get_host(ctx) .. ctx.var.uri
end

local function gen_lasttime_key(ctx)
    return "unhealthy-lasttime" .. core.request.get_host(ctx) .. ctx.var.uri
end

-- Ratio-policy state is scoped to the plugin's configuration identity
-- (route/service + config version), not the request URI. Keying by URI
-- would let a high-cardinality or wildcard route create unbounded entries
-- in the shared dict; keying by conf_version also means updating the
-- plugin's config starts the breaker fresh instead of inheriting counters
-- collected under a different configuration (same approach as the
-- limit-count and limit-conn plugins).
local function gen_breaker_id(ctx)
    return (ctx.conf_type or "") .. "#" .. (ctx.conf_id or "") .. "#" ..
            (ctx.conf_version or "")
end

local function gen_state_key(id)
    return "cb-state-" .. id
end

local function gen_last_state_change_key(id)
    return "cb-last-change-" .. id
end

local function gen_half_open_calls_key(id)
    return "cb-half-open-calls-" .. id
end

local function gen_half_open_success_key(id)
    return "cb-half-open-success-" .. id
end

local function gen_half_open_completed_key(id)
    return "cb-half-open-completed-" .. id
end

local function gen_transition_lock_key(id)
    return "cb-transition-" .. id
end

local function get_bucket_size(window_size)
    local size = math.floor((window_size or 300) / NUM_BUCKETS)
    if size < 1 then
        size = 1
    end
    return size
end

local function gen_bucket_req_key(id, bucket_size, epoch)
    return "cb-breq-" .. id .. "-" .. bucket_size .. "-" .. epoch
end

local function gen_bucket_fail_key(id, bucket_size, epoch)
    return "cb-bfail-" .. id .. "-" .. bucket_size .. "-" .. epoch
end

local _M = {
    version = 0.1,
    name = plugin_name,
    priority = 1005,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

-- State/half-open bookkeeping needs to outlive the OPEN wait plus the
-- half-open evaluation, but must still be bounded so idle routes don't hold
-- shared-dict entries forever.
local function get_state_ttl(conf)
    return (conf.max_breaker_sec or 300) * 4
end

-- Bucket entries must remain readable for the full span of buckets a
-- sliding-window sum can touch, plus a little slack.
local function get_bucket_ttl(bucket_size)
    return bucket_size * (NUM_BUCKETS + 1)
end

-- Circuit breaker state management functions
local function get_circuit_breaker_state(id)
    local state, err = shared_buffer:get(gen_state_key(id))
    if err then
        core.log.warn("failed to get circuit breaker state: ", err)
        return CLOSED
    end
    return state or CLOSED
end

local function set_circuit_breaker_state(conf, id, state)
    local ttl = get_state_ttl(conf)
    local current_time = ngx.time()

    shared_buffer:set(gen_state_key(id), state, ttl)
    shared_buffer:set(gen_last_state_change_key(id), current_time, ttl)

    core.log.info("api-breaker: state changed to ", state, " for ", id, " at ", current_time)
end

-- Sliding window bookkeeping (ratio policy). Each bucket is named after the
-- epoch it belongs to, so it never needs to be raced-over by concurrent
-- requests deciding whether to reset it -- a bucket for an epoch outside the
-- window simply isn't summed, and eventually expires via its own TTL.
local function record_window_sample(conf, id, is_failure)
    local window_size = conf.unhealthy.sliding_window_size or 300
    local bucket_size = get_bucket_size(window_size)
    local ttl = get_bucket_ttl(bucket_size)
    local epoch = math.floor(ngx.time() / bucket_size)

    local _, err = shared_buffer:incr(gen_bucket_req_key(id, bucket_size, epoch), 1, 0, ttl)
    if err then
        core.log.warn("failed to incr window request bucket: ", err)
    end

    if is_failure then
        local _, ferr = shared_buffer:incr(
            gen_bucket_fail_key(id, bucket_size, epoch), 1, 0, ttl)
        if ferr then
            core.log.warn("failed to incr window failure bucket: ", ferr)
        end
    end
end

local function sum_window(conf, id)
    local window_size = conf.unhealthy.sliding_window_size or 300
    local bucket_size = get_bucket_size(window_size)
    local current_epoch = math.floor(ngx.time() / bucket_size)

    local total_requests = 0
    local total_failures = 0
    for i = 0, NUM_BUCKETS - 1 do
        local epoch = current_epoch - i
        total_requests = total_requests +
                (shared_buffer:get(gen_bucket_req_key(id, bucket_size, epoch)) or 0)
        total_failures = total_failures +
                (shared_buffer:get(gen_bucket_fail_key(id, bucket_size, epoch)) or 0)
    end

    return total_requests, total_failures
end

local function clear_window(conf, id)
    local window_size = conf.unhealthy.sliding_window_size or 300
    local bucket_size = get_bucket_size(window_size)
    local current_epoch = math.floor(ngx.time() / bucket_size)

    for i = 0, NUM_BUCKETS - 1 do
        local epoch = current_epoch - i
        shared_buffer:delete(gen_bucket_req_key(id, bucket_size, epoch))
        shared_buffer:delete(gen_bucket_fail_key(id, bucket_size, epoch))
    end
end

local function open_breaker(conf, id)
    set_circuit_breaker_state(conf, id, OPEN)
    shared_buffer:delete(gen_half_open_calls_key(id))
    shared_buffer:delete(gen_half_open_success_key(id))
    shared_buffer:delete(gen_half_open_completed_key(id))
end

local function close_breaker(conf, id)
    shared_buffer:delete(gen_state_key(id))
    shared_buffer:delete(gen_last_state_change_key(id))
    shared_buffer:delete(gen_half_open_calls_key(id))
    shared_buffer:delete(gen_half_open_success_key(id))
    shared_buffer:delete(gen_half_open_completed_key(id))
    -- give the route a fresh start instead of reopening on pre-recovery history
    clear_window(conf, id)
end

local function break_response(conf, ctx)
    if conf.break_response_body then
        if conf.break_response_headers then
            for _, value in ipairs(conf.break_response_headers) do
                local val = core.utils.resolve_var(value.value, ctx.var)
                core.response.add_header(value.key, val)
            end
        end
        return conf.break_response_code, conf.break_response_body
    end
    return conf.break_response_code
end

-- Count-based circuit breaker (based on latest APISIX version)
local function count_based_access(conf, ctx)
    local unhealthy_key = gen_unhealthy_key(ctx)
    -- unhealthy counts
    local unhealthy_count, err = shared_buffer:get(unhealthy_key)
    if err then
        core.log.warn("failed to get unhealthy_key: ",
                      unhealthy_key, " err: ", err)
        return
    end

    if not unhealthy_count then
        return
    end

    -- timestamp of the last time a unhealthy state was triggered
    local lasttime_key = gen_lasttime_key(ctx)
    local lasttime, err = shared_buffer:get(lasttime_key)
    if err then
        core.log.warn("failed to get lasttime_key: ",
                      lasttime_key, " err: ", err)
        return
    end

    if not lasttime then
        return
    end

    local failure_times = math.floor(unhealthy_count / conf.unhealthy.failures)
    if failure_times < 1 then
        failure_times = 1
    end

    -- cannot exceed the maximum value of the user configuration
    local breaker_time = 2 ^ failure_times
    if breaker_time > conf.max_breaker_sec then
        breaker_time = conf.max_breaker_sec
    end
    core.log.info("breaker_time: ", breaker_time)

    -- breaker
    if lasttime + breaker_time >= ngx.time() then
        return break_response(conf, ctx)
    end

    return
end

-- Ratio-based circuit breaker
local function ratio_based_access(conf, ctx)
    local id = gen_breaker_id(ctx)
    local current_state = get_circuit_breaker_state(id)

    if current_state == OPEN then
        local last_change_time, err = shared_buffer:get(gen_last_state_change_key(id))
        if err then
            core.log.warn("failed to get last change time: ", err)
            return break_response(conf, ctx)
        end

        local wait_duration = conf.max_breaker_sec or 300
        if not last_change_time or (ngx.time() - last_change_time) < wait_duration then
            return break_response(conf, ctx)
        end

        -- Try to become the single request that flips OPEN -> HALF_OPEN. The
        -- lock's own short TTL is the debounce window: any other request
        -- that also observed OPEN and raced in here gets conservatively
        -- rejected as still-open rather than risking an admitted-but-
        -- uncounted probe slipping past half_open_max_calls.
        local won, add_err = shared_buffer:add(gen_transition_lock_key(id), 1, 1)
        if add_err then
            core.log.warn("failed to add transition lock: ", add_err)
        end

        if not won then
            return break_response(conf, ctx)
        end

        set_circuit_breaker_state(conf, id, HALF_OPEN)
        local half_open_ttl = get_state_ttl(conf)
        shared_buffer:set(gen_half_open_calls_key(id), 0, half_open_ttl)
        shared_buffer:set(gen_half_open_success_key(id), 0, half_open_ttl)
        shared_buffer:set(gen_half_open_completed_key(id), 0, half_open_ttl)
        core.log.info("api-breaker: transitioned from OPEN to HALF_OPEN for ", id)

        -- Fall through so this request is admitted (and counted) as the
        -- first half-open probe, instead of getting a free, uncounted pass.
        current_state = HALF_OPEN
    end

    if current_state == HALF_OPEN then
        local permitted_calls = conf.unhealthy.half_open_max_calls or 3
        local half_open_calls, err = shared_buffer:incr(
            gen_half_open_calls_key(id), 1, 0, get_state_ttl(conf))
        if err then
            core.log.warn("failed to increment half-open calls: ", err)
        end

        if half_open_calls > permitted_calls then
            return break_response(conf, ctx)
        end

        return
    end

    -- CLOSED: allow the request through; the decision to trip the breaker
    -- is made in the log phase once the response outcome is known.
    return
end

function _M.access(conf, ctx)
    if conf.policy == "unhealthy-ratio" then
        return ratio_based_access(conf, ctx)
    else
        -- Default to count-based (unhealthy-count)
        return count_based_access(conf, ctx)
    end
end

-- Count-based logging (based on latest APISIX version)
local function count_based_log(conf, ctx)
    local unhealthy_key = gen_unhealthy_key(ctx)
    local healthy_key = gen_healthy_key(ctx)
    local upstream_status = core.response.get_upstream_status(ctx)

    if not upstream_status then
        return
    end

    -- unhealthy process
    if core.table.array_find(conf.unhealthy.http_statuses,
                             upstream_status)
    then
        local unhealthy_count, err = shared_buffer:incr(unhealthy_key, 1, 0)
        if err then
            core.log.warn("failed to incr unhealthy_key: ", unhealthy_key,
                          " err: ", err)
        end
        core.log.info("unhealthy_key: ", unhealthy_key, " count: ",
                      unhealthy_count)

        shared_buffer:delete(healthy_key)

        -- whether the user-configured number of failures has been reached,
        -- and if so, the timestamp for entering the unhealthy state.
        if unhealthy_count % conf.unhealthy.failures == 0 then
            shared_buffer:set(gen_lasttime_key(ctx), ngx.time(),
                              conf.max_breaker_sec)
            core.log.info("update unhealthy_key: ", unhealthy_key, " to ",
                          unhealthy_count)
        end

        return
    end

    -- health process
    if not core.table.array_find(conf.healthy.http_statuses, upstream_status) then
        return
    end

    local unhealthy_count, err = shared_buffer:get(unhealthy_key)
    if err then
        core.log.warn("failed to `get` unhealthy_key: ", unhealthy_key,
                      " err: ", err)
    end

    if not unhealthy_count then
        return
    end

    local healthy_count, err = shared_buffer:incr(healthy_key, 1, 0)
    if err then
        core.log.warn("failed to `incr` healthy_key: ", healthy_key,
                      " err: ", err)
    end

    -- clear related status
    if healthy_count >= conf.healthy.successes then
        -- stat change to normal
        core.log.info("change to normal, ", healthy_key, " ", healthy_count)
        shared_buffer:delete(gen_lasttime_key(ctx))
        shared_buffer:delete(unhealthy_key)
        shared_buffer:delete(healthy_key)
    end

    return
end

-- Ratio-based logging
local function ratio_based_log(conf, ctx)
    local upstream_status = core.response.get_upstream_status(ctx)
    if not upstream_status then
        return
    end

    local id = gen_breaker_id(ctx)
    local current_state = get_circuit_breaker_state(id)

    local is_failure = core.table.array_find(conf.unhealthy.http_statuses, upstream_status)
    local is_success = not is_failure and
            core.table.array_find(conf.healthy.http_statuses, upstream_status)

    if current_state == HALF_OPEN then
        if is_failure then
            -- Fail fast: any failed probe reopens the breaker immediately.
            core.log.warn("api-breaker: half-open probe failed for ", id,
                    ", reopening")
            open_breaker(conf, id)
            return
        end

        if is_success then
            shared_buffer:incr(gen_half_open_success_key(id), 1, 0, get_state_ttl(conf))
        end

        -- Count every probe that reaches the log phase, regardless of how
        -- its status was classified, so a status that's neither a
        -- configured success nor failure can't strand the breaker in
        -- HALF_OPEN forever waiting for a classification that will never
        -- come. Probes that the access phase rejected for exceeding
        -- half_open_max_calls never reach here, so they can't corrupt this
        -- count either.
        local permitted_calls = conf.unhealthy.half_open_max_calls or 3
        local completed, err = shared_buffer:incr(
            gen_half_open_completed_key(id), 1, 0, get_state_ttl(conf))
        if err then
            core.log.warn("failed to increment half-open completed calls: ", err)
            return
        end

        if completed >= permitted_calls then
            local success_count = shared_buffer:get(gen_half_open_success_key(id)) or 0
            local success_ratio = (conf.healthy and conf.healthy.success_ratio) or 0.6

            if (success_count / completed) >= success_ratio then
                core.log.info("api-breaker: half-open success ratio ",
                        success_count / completed, " >= threshold ", success_ratio,
                        ", closing for ", id)
                close_breaker(conf, id)
            else
                core.log.warn("api-breaker: half-open success ratio ",
                        success_count / completed, " < threshold ", success_ratio,
                        ", reopening for ", id)
                open_breaker(conf, id)
            end
        end

        return
    end

    if current_state == OPEN then
        -- access() should already be blocking requests while OPEN; avoid
        -- polluting the closed-state window if one still slips through.
        return
    end

    -- CLOSED: record this response and check whether the error ratio over
    -- the sliding window now crosses the configured threshold.
    record_window_sample(conf, id, is_failure)

    local min_requests = conf.unhealthy.min_request_threshold or 10
    local error_ratio = conf.unhealthy.error_ratio or 0.5
    local total_requests, total_failures = sum_window(conf, id)

    if total_requests >= min_requests then
        local failure_rate = total_failures / total_requests
        if failure_rate >= error_ratio then
            core.log.warn("api-breaker: error ratio ", failure_rate,
                    " >= threshold ", error_ratio, ", opening for ", id)
            open_breaker(conf, id)
        end
    end
end

function _M.log(conf, ctx)
    if conf.policy == "unhealthy-ratio" then
        ratio_based_log(conf, ctx)
    else
        -- Default to count-based (unhealthy-count)
        count_based_log(conf, ctx)
    end
end

return _M
