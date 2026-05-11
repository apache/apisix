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
local secret = require("apisix.secret")
local plugin = require("apisix.plugin")
local ov   = require("resty.openapi_validator")
local http = require("resty.http")
local ngx_req = ngx.req
local ngx_md5 = ngx.md5
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local tab_sort = table.sort
local tab_concat = table.concat

local plugin_name = "oas-validator"

local DEFAULT_SPEC_URL_TTL = 3600

local schema = {
    type = "object",
    properties = {
        spec = {
            description = "schema against which the request/response will be validated",
            type = "string",
            minLength = 1
        },
        spec_url = {
            description = "URL to fetch the OpenAPI spec from",
            type = "string",
            pattern = [[^https?://]],
        },
        spec_url_request_headers = {
            description = "custom HTTP headers to include when fetching spec_url",
            type = "object",
            additionalProperties = {
                type = "string",
            },
        },
        ssl_verify = {
            description = "whether to verify SSL certificate when fetching spec_url",
            type = "boolean",
            default = false,
        },
        timeout = {
            description = "HTTP request timeout in milliseconds for fetching spec_url",
            type = "integer",
            minimum = 1000,
            maximum = 60000,
            default = 10000,
        },
        verbose_errors = {
            type = "boolean",
            default = false
        },
        skip_request_body_validation = {
            type = "boolean",
            default = false
        },
        skip_request_header_validation = {
            type = "boolean",
            default = false
        },
        skip_query_param_validation  = {
            type = "boolean",
            default = false
        },
        skip_path_params_validation  = {
            type = "boolean",
            default = false
        },
        reject_if_not_match = {
            type = "boolean",
            default = true
        },
        rejection_status_code = {
            description = "HTTP status code to return when request validation fails",
            type = "integer",
            minimum = 400,
            maximum = 599,
            default = 400
        }
    },
    oneOf = {
        {required = {"spec"}},
        {required = {"spec_url"}},
    },
}

local metadata_schema = {
    type = "object",
    properties = {
        spec_url_ttl = {
            description = "TTL in seconds for cached spec fetched from spec_url",
            type = "integer",
            minimum = 1,
            default = DEFAULT_SPEC_URL_TTL,
        },
    },
}

local spec_url_lrucache
local spec_url_lrucache_ttl

local function get_spec_url_ttl()
    local metadata = plugin.plugin_metadata(plugin_name)
    if metadata and metadata.value and metadata.value.spec_url_ttl then
        return metadata.value.spec_url_ttl
    end
    return DEFAULT_SPEC_URL_TTL
end

local function get_spec_url_lrucache()
    local ttl = get_spec_url_ttl()
    if not spec_url_lrucache or spec_url_lrucache_ttl ~= ttl then
        spec_url_lrucache = core.lrucache.new({
            ttl = ttl,
            count = 512,
            invalid_stale = true,
            refresh_stale = true,
            serial_creating = true,
        })
        spec_url_lrucache_ttl = ttl
    end
    return spec_url_lrucache
end

local function fetch_and_compile(conf)
    local httpc = http.new()
    httpc:set_timeout(conf.timeout or 10000)

    local params = {
        method = "GET",
        ssl_verify = conf.ssl_verify or false,
    }
    if conf.spec_url_request_headers then
        params.headers = conf.spec_url_request_headers
    end

    local res, err = httpc:request_uri(conf.spec_url, params)
    if not res then
        return nil, "failed to fetch spec from URL: " .. err
    end

    if res.status ~= 200 then
        return nil, "spec URL returned status " .. res.status
    end

    local validator, err = ov.compile(res.body)
    if not validator then
        return nil, "failed to compile openapi spec fetched from URL: " .. err
    end

    return validator
end

local _M = {
    version = 0.1,
    priority = 512,
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end

    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if conf.spec and not secret.is_secret_ref(conf.spec) then
        local _, decode_err = core.json.decode(conf.spec)
        if decode_err then
            return false, "invalid JSON string provided, err: " .. decode_err
        end
    end

    return true
end


local function get_validator(conf)
    if conf.spec then
        conf._meta = conf._meta or {}
        if not conf._meta.validator then
            local validator, err = ov.compile(conf.spec)
            if not validator then
                return nil, "failed to compile openapi spec, err: " .. err
            end
            conf._meta.validator = validator
        end
        return conf._meta.validator
    end

    local lrucache = get_spec_url_lrucache()
    local ssl_verify = conf.ssl_verify or false
    local cache_key = conf.spec_url .. "#ssl_verify=" .. tostring(ssl_verify)
    if conf.spec_url_request_headers then
        local sorted_keys = {}
        for k in pairs(conf.spec_url_request_headers) do
            sorted_keys[#sorted_keys + 1] = k
        end
        tab_sort(sorted_keys)
        local parts = {}
        for _, k in ipairs(sorted_keys) do
            parts[#parts + 1] = k .. "=" .. conf.spec_url_request_headers[k]
        end
        cache_key = cache_key .. "#" .. ngx_md5(tab_concat(parts, "&"))
    end
    local validator, err = lrucache(cache_key, nil, fetch_and_compile, conf)
    if not validator then
        return nil, err
    end
    return validator
end


function _M.access(conf, ctx)
    local validator, err = get_validator(conf)
    if not validator then
        core.log.error(err)
        return 500, {message = "failed to parse openapi spec"}
    end

    local req_body
    if not conf.skip_request_body_validation then
        local body, body_err = core.request.get_body()
        if body_err ~= nil then
            core.log.error("failed reading request body, err: " .. body_err)
            return 500, {message = "error reading the request body. err: " .. body_err}
        end
        req_body = body
    end

    local headers
    if not conf.skip_request_header_validation then
        local h, h_err = ngx_req.get_headers(0, true)
        if h_err ~= nil then
            core.log.error("failed reading request headers, err: " .. h_err)
            return 500, {message = "error reading the request headers, err: " .. h_err}
        end
        headers = h
    end

    local query
    if not conf.skip_query_param_validation then
        query = core.request.get_uri_args(ctx)
    end

    local ok, validate_err = validator:validate_request({
        method       = core.request.get_method(),
        path         = ctx.var.uri,
        query        = query,
        headers      = headers,
        body         = req_body,
        content_type = ctx.var.content_type,
    }, {
        path   = conf.skip_path_params_validation,
        query  = conf.skip_query_param_validation,
        header = conf.skip_request_header_validation,
        body   = conf.skip_request_body_validation,
    })

    if not ok then
        core.log.error("error occurred while validating request [" ..
            core.request.get_method() .. " " .. ctx.var.uri,
            "], err: " .. validate_err)

        if conf.reject_if_not_match then
            if not conf.verbose_errors then
                validate_err = ""
            end
            return conf.rejection_status_code,
                   {message = "failed to validate request. " .. validate_err}
        end
    end
end

return _M
