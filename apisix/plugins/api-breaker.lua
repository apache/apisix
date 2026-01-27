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
            description = "Circuit breaker duration in seconds (applies to both count and ratio policies)"
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
                            description = "Minimum number of calls before circuit breaker can be triggered"
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
                            description = "Number of permitted calls when circuit breaker is half-open"
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
                            description = "Success rate threshold to close circuit breaker from half-open state"
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

-- New key generation functions for ratio policy
local function gen_state_key(ctx)
    return "cb-state-" .. core.request.get_host(ctx) .. ctx.var.uri
end

local function gen_total_requests_key(ctx)
    return "cb-total-" .. core.request.get_host(ctx) .. ctx.var.uri
end

local function gen_window_start_time_key(ctx)
    return "cb-window-" .. core.request.get_host(ctx) .. ctx.var.uri
end

local function gen_last_state_change_key(ctx)
    return "cb-last-change-" .. core.request.get_host(ctx) .. ctx.var.uri
end

local function gen_half_open_calls_key(ctx)
    return "cb-half-open-calls-" .. core.request.get_host(ctx) .. ctx.var.uri
end

local function gen_half_open_success_key(ctx)
    return "cb-half-open-success-" .. core.request.get_host(ctx) .. ctx.var.uri
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

-- Circuit breaker state management functions
local function get_circuit_breaker_state(ctx)
  local state_key = gen_state_key(ctx)
  local state, err = shared_buffer:get(state_key)
  if err then
    core.log.warn("failed to get circuit breaker state: ", err)
    return CLOSED
  end
  return state or CLOSED
end

local function set_circuit_breaker_state(ctx, state)
  local state_key = gen_state_key(ctx)
  local last_change_key = gen_last_state_change_key(ctx)
  local current_time = ngx.time()

  shared_buffer:set(state_key, state)
  shared_buffer:set(last_change_key, current_time)

  core.log.info("Circuit breaker state changed to: ", state, " at: ", current_time)
end

-- Sliding window management
local function reset_sliding_window(ctx, current_time, window_size)
  local window_start_key = gen_window_start_time_key(ctx)
  local total_requests_key = gen_total_requests_key(ctx)
  local unhealthy_key = gen_unhealthy_key(ctx)

  shared_buffer:set(window_start_key, current_time)
  shared_buffer:set(total_requests_key, 0)
  shared_buffer:set(unhealthy_key, 0)

  -- Reset circuit breaker state to CLOSED when sliding window resets
  shared_buffer:delete(gen_state_key(ctx))
  shared_buffer:delete(gen_last_state_change_key(ctx))
  shared_buffer:delete(gen_half_open_calls_key(ctx))
  shared_buffer:delete(gen_half_open_success_key(ctx))

  core.log.info("Sliding window reset at: ", current_time, " window size: ", window_size, "s")
end

local function check_and_reset_window(ctx, conf)
  local current_time = ngx.time()
  local window_start_key = gen_window_start_time_key(ctx)
  local window_start_time, err = shared_buffer:get(window_start_key)

  if err then
    core.log.warn("failed to get window start time: ", err)
    return
  end

  local window_size = conf.unhealthy.sliding_window_size or 300

  if not window_start_time or (current_time - window_start_time) >= window_size then
    reset_sliding_window(ctx, current_time, window_size)
  end
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

    return
end

-- Ratio-based circuit breaker
local function ratio_based_access(conf, ctx)
    -- Check and reset sliding window first to ensure consistent state
    check_and_reset_window(ctx, conf)

    local current_state = get_circuit_breaker_state(ctx)
    local current_time = ngx.time()

    -- Handle OPEN state
    if current_state == OPEN then
        local last_change_key = gen_last_state_change_key(ctx)
        local last_change_time, err = shared_buffer:get(last_change_key)
        if err then
            core.log.warn("failed to get last change time: ", err)
            return conf.break_response_code or 503,
                    conf.break_response_body or "Service temporarily unavailable"
        end

        local wait_duration = conf.max_breaker_sec or 60
        if last_change_time and (current_time - last_change_time) >= wait_duration then
            -- Transition to HALF_OPEN
            set_circuit_breaker_state(ctx, HALF_OPEN)
            -- Reset half-open counters
            shared_buffer:set(gen_half_open_calls_key(ctx), 0)
            shared_buffer:set(gen_half_open_success_key(ctx), 0)
            core.log.info("Circuit breaker transitioned from OPEN to HALF_OPEN")
            return -- Allow this request to pass
        else
            -- Still in OPEN state, reject request
            if conf.break_response_headers then
                for _, value in ipairs(conf.break_response_headers) do
                    local val = core.utils.resolve_var(value.value, ctx.var)
                    core.response.add_header(value.key, val)
                end
            end
            return conf.break_response_code or 503,
                    conf.break_response_body or "Service temporarily unavailable"
        end
    end

    -- Handle HALF_OPEN state
    if current_state == HALF_OPEN then
        local half_open_calls_key = gen_half_open_calls_key(ctx)
        local half_open_calls, err = shared_buffer:incr(half_open_calls_key, 1, 0)
        if err then
            core.log.warn("failed to increment half-open calls: ", err)
        end

        local permitted_calls = conf.unhealthy.half_open_max_calls or 3
        if half_open_calls > permitted_calls then
            -- Too many calls in half-open state, reject
            return conf.break_response_code or 503,
                    conf.break_response_body or "Service temporarily unavailable"
        end

        -- Allow request to pass for evaluation
        return
    end

    -- CLOSED state - check if we should transition to OPEN
    local total_requests_key = gen_total_requests_key(ctx)
    local unhealthy_key = gen_unhealthy_key(ctx)

    local total_requests, err = shared_buffer:get(total_requests_key)
    if err then
        core.log.warn("failed to get total requests: ", err)
        return
    end

    local unhealthy_count, err = shared_buffer:get(unhealthy_key)
    if err then
        core.log.warn("failed to get unhealthy count: ", err)
        return
    end

    if total_requests and unhealthy_count and total_requests > 0 then
        local minimum_calls = conf.unhealthy.min_request_threshold or 10
        local failure_threshold = conf.unhealthy.error_ratio or 0.5

        if total_requests >= minimum_calls then
            local failure_rate = unhealthy_count / total_requests
            -- Use precise comparison to avoid floating point issues
            local rounded_failure_rate = math.floor(failure_rate * 10000 + 0.5) / 10000
            local rounded_threshold = math.floor(failure_threshold * 10000 + 0.5) / 10000

            core.log.info("Circuit breaker check - total: ", total_requests,
                    " failures: ", unhealthy_count,
                    " rate: ", rounded_failure_rate,
                    " threshold: ", rounded_threshold)

            if rounded_failure_rate >= rounded_threshold then
                -- Transition to OPEN state
                set_circuit_breaker_state(ctx, OPEN)
                core.log.warn("Circuit breaker OPENED - failure rate: ", rounded_failure_rate,
                        " >= threshold: ", rounded_threshold)
                return conf.break_response_code or 503,
                        conf.break_response_body or "Service temporarily unavailable"
            end
        end
    end

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

    local current_state = get_circuit_breaker_state(ctx)

    -- Increment total request counter
    local total_requests_key = gen_total_requests_key(ctx)
    local total_requests, err = shared_buffer:incr(total_requests_key, 1, 0)
    if err then
        core.log.warn("failed to increment total requests: ", err)
    end

    -- Handle response based on status
    local is_failure = core.table.array_find(conf.unhealthy.http_statuses, upstream_status)
    local is_success = not is_failure and
            core.table.array_find(conf.healthy.http_statuses, upstream_status)

    if is_failure then
        -- Increment failure counter
        local unhealthy_key = gen_unhealthy_key(ctx)
        local unhealthy_count, err = shared_buffer:incr(unhealthy_key, 1, 0)
        if err then
            core.log.warn("failed to increment unhealthy count: ", err)
        end

        core.log.info("Request failed - status: ", upstream_status,
                " total: ", total_requests,
                " failures: ", unhealthy_count)

        -- If in HALF_OPEN state and got a failure, immediately go back to OPEN
        if current_state == HALF_OPEN then
            set_circuit_breaker_state(ctx, OPEN)
            core.log.warn("Circuit breaker returned to OPEN state due to failure in HALF_OPEN")
            -- Clean up half-open counters
            shared_buffer:delete(gen_half_open_calls_key(ctx))
            shared_buffer:delete(gen_half_open_success_key(ctx))
        end
    elseif is_success then
        core.log.info("Request succeeded - status: ", upstream_status, " total: ", total_requests)

        -- Handle HALF_OPEN state success
        if current_state == HALF_OPEN then
            local half_open_success_key = gen_half_open_success_key(ctx)
            local success_count, err = shared_buffer:incr(half_open_success_key, 1, 0)
            if err then
                core.log.warn("failed to increment half-open success count: ", err)
            end

            local half_open_calls_key = gen_half_open_calls_key(ctx)
            local total_calls, err = shared_buffer:get(half_open_calls_key)
            if err then
                core.log.warn("failed to get half-open calls count: ", err)
                return
            end

            local permitted_calls = conf.unhealthy.half_open_max_calls or 3
            if total_calls and total_calls >= permitted_calls then
                -- Check success rate threshold
                local success_ratio = 0.6 -- Default value
                if conf.healthy and conf.healthy.success_ratio then
                    success_ratio = conf.healthy.success_ratio
                end

                local success_rate = success_count / total_calls
                if success_rate >= success_ratio then
                    -- Transition back to CLOSED state
                    set_circuit_breaker_state(ctx, CLOSED)
                    core.log.info("Circuit breaker transitioned from HALF_OPEN to CLOSED - success rate: ",
                            success_rate, " >= threshold: ", success_ratio)

                    -- Clean up all counters for fresh start
                    shared_buffer:delete(gen_half_open_calls_key(ctx))
                    shared_buffer:delete(gen_half_open_success_key(ctx))
                    shared_buffer:delete(gen_unhealthy_key(ctx))
                    shared_buffer:delete(gen_total_requests_key(ctx))
                    shared_buffer:delete(gen_window_start_time_key(ctx))
                else
                    -- Success rate too low, return to OPEN state
                    set_circuit_breaker_state(ctx, OPEN)
                    core.log.warn("Circuit breaker returned to OPEN state - success rate: ",
                            success_rate, " < threshold: ", success_ratio)
                    -- Clean up half-open counters
                    shared_buffer:delete(gen_half_open_calls_key(ctx))
                    shared_buffer:delete(gen_half_open_success_key(ctx))
                end
            end
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
