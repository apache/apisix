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
local type         = type
local pairs        = pairs
local math_random  = math.random
local ngx          = ngx

local http            = require("resty.http")
local bp_manager_mod  = require("apisix.utils.batch-processor-manager")
local core            = require("apisix.core")
local str_format      = core.string.format

local plugin_name = "lago"
local batch_processor_manager = bp_manager_mod.new("lago logger")

local schema = {
    type = "object",
    properties = {
        -- core configurations
        endpoint_addrs = {
            type = "array",
            minItems = 1,
            items = core.schema.uri_def,
            description = "Lago API address, like https://api.getlago.com, "
                        .. "it supports both cloud and self-hosted, "
                        .. "one of them is randomly selected when configured as more than one",
        },
        endpoint_uri = {
            type = "string",
            minLength = 1,
            default = "/api/v1/events/batch",
            description = "Lago API endpoint, it needs to be set to the batch send endpoint",
        },
        token = {
            type = "string",
            description = "Lago API API key, create one for your organization on dashboard"
        },
        event_transaction_id = {
            type = "string",
            description = "Event's transaction ID, it is used to identify and de-duplicate"
                        .. " the event, it supports string templates containing APISIX and"
                        .. " NGINX variables, like \"req_${request_id}\", which allows you"
                        .. " to use values returned by upstream services or request-id"
                        .. " plugin integration",
        },
        event_subscription_id = {
            type = "string",
            description = "Event's subscription ID, which is automatically generated or"
                        .. " specified by you when you assign the plan to the customer on"
                        .. " Lago, used to associate API consumption to a customer subscription,"
                        .. " it supports string templates containing APISIX and NGINX variables,"
                        .. " like \"cus_${consumer_name}\", which allows you to use values"
                        .. " returned by upstream services or APISIX consumer",
        },
        event_code = {
            type = "string",
            description = "Lago billable metric's code for associating an event to a specified"
                        .. "billable item",
        },
        event_properties = {
            type = "object",
            patternProperties = {
                [".*"] = {
                    type = "string",
                    minLength = 1,
                },
            },
            description = "Event's properties, used to attach information to an event, this"
                        .. " allows you to send certain information on a request to Lago, such"
                        .. " as sending HTTP status to take a failed request off the bill, or"
                        .. " sending the AI token consumption in the response body for accurate"
                        .. " billing, its keys are fixed strings and its values can be string"
                        .. " templates containing APISIX and NGINX variables, like \"${status}\""
        },

        -- connection layer configurations
        ssl_verify = {type = "boolean", default = true},
        timeout = {
            type = "integer",
            minimum = 1,
            maximum = 60000,
            default = 3000,
            description = "timeout in milliseconds",
        },
        keepalive = {type = "boolean", default = true},
        keepalive_timeout = {
            type = "integer",
            minimum = 1000,
            default = 60000,
            description = "keepalive timeout in milliseconds",
        },
        keepalive_pool = {type = "integer", minimum = 1, default = 5},
    },
    required = {"endpoint_addrs", "token", "event_transaction_id", "event_subscription_id",
                "event_code"}
}
schema = batch_processor_manager:wrap_schema(schema)

-- According to https://getlago.com/docs/api-reference/events/batch, the maximum batch size is 100,
-- so we have to override the default batch size to make it work out of the box，the plugin does
-- not set a maximum limit, so if Lago relaxes the limit, then user can modify it
-- to a larger batch size
-- This does not affect other plugins, schema is appended after deep copy
schema.properties.batch_max_size.default = 100


local _M = {
    version = 0.1,
    priority = 415,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf, schema_type)
    local check = {"endpoint_addrs"}
    core.utils.check_https(check, conf, plugin_name)
    core.utils.check_tls_bool({"ssl_verify"}, conf, plugin_name)

    return core.schema.check(schema, conf)
end


local function send_http_data(conf, data)
    local params = {
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. conf.token,
        },
        keepalive = conf.keepalive,
        ssl_verify = conf.ssl_verify,
        method = "POST",
        body = core.json.encode(data)
    }

    if conf.keepalive then
        params.keepalive_timeout = conf.keepalive_timeout
        params.keepalive_pool = conf.keepalive_pool
    end

    local httpc, err = http.new()
    if not httpc then
        return false, str_format("create http client error: %s", err)
    end
    httpc:set_timeout(conf.timeout)

    -- select an random endpoint and build URL
    local endpoint_url = conf.endpoint_addrs[math_random(#conf.endpoint_addrs)]..conf.endpoint_uri
    local res, err = httpc:request_uri(endpoint_url, params)
    if not res then
        return false, err
    end

    if res.status >= 300 then
        return false, str_format("lago api returned status: %d, body: %s",
            res.status, res.body or "")
    end

    return true
end


function _M.log(conf, ctx)
    -- build usage event
    local event_transaction_id, err = core.utils.resolve_var(conf.event_transaction_id, ctx.var)
    if err then
        core.log.error("failed to resolve event_transaction_id, event dropped: ", err)
        return
    end

    local event_subscription_id, err = core.utils.resolve_var(conf.event_subscription_id, ctx.var)
    if err then
        core.log.error("failed to resolve event_subscription_id, event dropped: ", err)
        return
    end

    local entry = {
        transaction_id = event_transaction_id,
        external_subscription_id = event_subscription_id,
        code = conf.event_code,
        timestamp = ngx.req.start_time(),
    }

    if conf.event_properties and type(conf.event_properties) == "table" then
        entry.properties = core.table.deepcopy(conf.event_properties)
        for key, value in pairs(entry.properties) do
            local new_val, err, n_resolved = core.utils.resolve_var(value, ctx.var)
            if not err and n_resolved > 0 then
                entry.properties[key] = new_val
            end
        end
    end

    if batch_processor_manager:add_entry(conf, entry) then
        return
    end

    -- generate a function to be executed by the batch processor
    local func = function(entries)
        return send_http_data(conf, {
            events = entries,
        })
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, func)
end


return _M
