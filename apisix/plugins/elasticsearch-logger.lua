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
local core            = require("apisix.core")
local http            = require("resty.http")
local log_util        = require("apisix.utils.log-util")
local bp_manager_mod  = require("apisix.utils.batch-processor-manager")
local ngx             = ngx
local ngx_re          = ngx.re
local str_format      = core.string.format
local math_random     = math.random
local os_date         = os.date
local pcall           = pcall
local type            = type
local pairs           = pairs
local ipairs          = ipairs
local setmetatable    = setmetatable

local plugin_name = "elasticsearch-logger"
local batch_processor_manager = bp_manager_mod.new(plugin_name)

local schema = {
    type = "object",
    properties = {
        -- deprecated, use "endpoint_addrs" instead
        endpoint_addr = {
            type = "string",
            pattern = "[^/]$",
        },
        endpoint_addrs = {
            type = "array",
            minItems = 1,
            items = {
                type = "string",
                pattern = "[^/]$",
            },
        },
        field = {
            type = "object",
            properties = {
                index = { type = "string"},
            },
            required = {"index"}
        },
        log_format = {type = "object"},
        log_format_extra = {type = "object"},
        auth = {
            type = "object",
            properties = {
                username = {
                    type = "string",
                    minLength = 1
                },
                password = {
                    type = "string",
                    minLength = 1
                }
            },
            oneOf = {
                {required = {"username", "password"}},
            }
        },
        headers = {
            type = "object",
            minProperties = 1,
            patternProperties = {
                ["^[^:]+$"] = {
                    type = "string",
                    minLength = 1
                }
            },
            additionalProperties = false
        },
        timeout = {
            type = "integer",
            minimum = 1,
            default = 10
        },
        ssl_verify = {
            type = "boolean",
            default = true
        },
        include_req_body = {type = "boolean", default = false},
        include_req_body_expr = {
            type = "array",
            minItems = 1,
            items = {
                type = "array"
            }
        },
        include_resp_body = { type = "boolean", default = false },
        include_resp_body_expr = {
            type = "array",
            minItems = 1,
            items = {
                type = "array"
            }
        },
        max_req_body_bytes = { type = "integer", minimum = 1, default = 524288 },
        max_resp_body_bytes = { type = "integer", minimum = 1, default = 524288 },
    },
    encrypt_fields = {"auth.password", "headers"},
    oneOf = {
        {required = {"endpoint_addr", "field"}},
        {required = {"endpoint_addrs", "field"}}
    },
}


local metadata_schema = {
    type = "object",
    properties = {
        log_format_extra = {
            type = "object"
        },
        log_format = {
            type = "object"
        },
    },
}


local _M = {
    version = 0.1,
    priority = 413,
    name = plugin_name,
    schema = batch_processor_manager:wrap_schema(schema),
    metadata_schema = batch_processor_manager:wrap_metadata_schema(metadata_schema),
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end

    local check = {"endpoint_addrs"}
    core.utils.check_https(check, conf, plugin_name)
    core.utils.check_tls_bool({"ssl_verify"}, conf, plugin_name)
    return core.schema.check(schema, conf)
end


local function get_es_major_version(uri, conf)
    local httpc = http.new()
    if not httpc then
        return nil, "failed to create http client"
    end

    local headers = {}
    if conf.auth then
        local authorization = "Basic " .. ngx.encode_base64(
            conf.auth.username .. ":" .. conf.auth.password
        )
        headers["Authorization"] = authorization
    end

    if conf.headers then
        for k, v in pairs(conf.headers) do
            headers[k] = v
        end
    end

    httpc:set_timeout(conf.timeout * 1000)
    local res, err = httpc:request_uri(uri, {
        ssl_verify = conf.ssl_verify,
        method = "GET",
        headers = headers,
    })
    if not res then
        return false, err
    end
    if res.status ~= 200 then
        return nil, str_format("server returned status: %d, body: %s",
            res.status, res.body or "")
    end
    local json_body, err = core.json.decode(res.body)
    if not json_body then
        return nil, "failed to decode response body: " .. err
    end
    -- checked before use: a probe that raises would fail its batch, and the next one
    local version = type(json_body) == "table" and json_body.version
    if type(version) ~= "table" or type(version.number) ~= "string" then
        return nil, "failed to get version from response body"
    end

    local major_version = version.number:match("^(%d+)%.")
    if not major_version then
        return nil, "invalid version format: " .. version.number
    end

    return major_version
end


local function replace_time(m)
    local time_format = m[1]
    -- os.date returns a *table* (not a string) for the "*t"/"!*t" formats, and
    -- on non-LuaJIT runtimes can raise on a bad strftime escape. Either way the
    -- result would be stringified into a garbage index name, so require a
    -- string and fall back to an empty replacement otherwise.
    local ok, time = pcall(os_date, time_format)
    if not ok or type(time) ~= "string" then
        core.log.error("failed to parse time format: ", time_format)
        return ""
    end
    return time
end


local function resolve_index_vars(index, var)
    local new_index, _, err = ngx_re.gsub(index, "(?<!\\$){([^}]*)}", replace_time, "jo")
    if not new_index then
        core.log.error("failed to substitute time format: ", err)
    end

    new_index, err = core.utils.resolve_var(new_index or index, var)
    if not new_index then
        core.log.error("failed to resolve APISIX variable from index: ", err)
    end

    return new_index or index
end


-- The Elasticsearch major version of the cluster a batch processor's conf sends to,
-- or false once its probe has failed. It is not kept in the conf: plugin.conf_version()
-- caches in conf._version the version that keys the conf's batch processor, so a
-- major version stored there made every conf with that major version share one
-- processor, and so its endpoints and credentials.
local es_versions = setmetatable({}, {__mode = "k"})


-- The action line is added when the batch is sent, see send_to_elasticsearch().
local function get_logger_entry(conf, ctx, index)
    local entry = log_util.get_log_entry(plugin_name, conf, ctx)
    if entry == nil then
        -- not logged: `match` leaves the request out, or its body could not be read
        return nil
    end
    local doc, err = core.json.encode(entry)
    if not doc then
        -- an entry that cannot be encoded would fail every batch it is part of
        core.log.error("failed to encode the log entry: ", err)
        return nil
    end
    return {
        index = index,
        doc = doc,
    }
end


-- The version is probed from the batch timer, so that no request waits for it. Batches
-- sent before the first probe returns probe as well; after that, a failed probe is not
-- repeated: only Elasticsearch 5 and 6 need the version, while a cluster that refuses
-- GET / (it needs the `monitor` cluster privilege) would otherwise cost a request and
-- an error line for every batch.
local function fetch_and_update_es_version(conf)
    if es_versions[conf] ~= nil then
        return
    end

    local selected_endpoint_addr
    if conf.endpoint_addr then
        selected_endpoint_addr = conf.endpoint_addr
    else
        selected_endpoint_addr = conf.endpoint_addrs[math_random(#conf.endpoint_addrs)]
    end
    local major_version, err = get_es_major_version(selected_endpoint_addr, conf)
    if err then
        core.log.error("failed to get Elasticsearch version: ", err)
        -- keep a version that a concurrent batch has got in the meantime
        if es_versions[conf] == nil then
            es_versions[conf] = false
        end
        return
    end
    es_versions[conf] = major_version
end


local function send_to_elasticsearch(conf, entries)
    local httpc, err = http.new()
    if not httpc then
        return false, str_format("create http error: %s", err)
    end

    -- Every action line of the batch is built here, from the version of the cluster
    -- this processor sends to: Elasticsearch 5 and 6 reject the whole bulk request
    -- when one of its action lines lacks the `_type` they need.
    fetch_and_update_es_version(conf)
    local es_version = es_versions[conf]
    local lines = core.table.new(#entries * 2, 0)
    for i, entry in ipairs(entries) do
        local action = {
            index = {
                _index = entry.index
            }
        }
        -- for older version type is required
        if es_version == "6" or es_version == "5" then
            action.index._type = "_doc"
        end
        lines[i * 2 - 1] = core.json.encode(action)
        lines[i * 2] = entry.doc
    end

    local selected_endpoint_addr
    if conf.endpoint_addr then
        selected_endpoint_addr = conf.endpoint_addr
    else
        selected_endpoint_addr = conf.endpoint_addrs[math_random(#conf.endpoint_addrs)]
    end
    local uri = selected_endpoint_addr .. "/_bulk"
    local body = core.table.concat(lines, "\n") .. "\n"
    local headers = {
        ["Content-Type"] = "application/x-ndjson",
        ["Accept"] = "application/vnd.elasticsearch+json"
    }
    if conf.auth then
        local authorization = "Basic " .. ngx.encode_base64(
            conf.auth.username .. ":" .. conf.auth.password
        )
        headers["Authorization"] = authorization
    end

    if conf.headers then
        for k, v in pairs(conf.headers) do
            headers[k] = v
        end
    end

    httpc:set_timeout(conf.timeout * 1000)
    local resp, err = httpc:request_uri(uri, {
        ssl_verify = conf.ssl_verify,
        method = "POST",
        headers = headers,
        body = body
    })
    if not resp then
        return false, err
    end

    if resp.status ~= 200 then
        return false, str_format("elasticsearch server returned status: %d, body: %s",
        resp.status, resp.body or "")
    end

    return true
end


function _M.body_filter(conf, ctx)
    log_util.collect_body(conf, ctx)
end


function _M.access(conf, ctx)
    log_util.check_and_read_req_body(conf, ctx)
end


function _M.log(conf, ctx)
    local index = resolve_index_vars(conf.field.index, ctx.var)
    local entry = get_logger_entry(conf, ctx, index)

    if batch_processor_manager:add_entry(conf, entry) then
        return
    end

    local process = function(entries)
        return send_to_elasticsearch(conf, entries)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, process)
end

_M._resolve_index_vars = resolve_index_vars

return _M
