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

local memory_handler = require("apisix.plugins.proxy-cache.memory_handler")
local disk_handler = require("apisix.plugins.proxy-cache.disk_handler")
local memory_strategy = require("apisix.plugins.proxy-cache.memory").new
local util = require("apisix.plugins.proxy-cache.util")
local apisix_plugin = require("apisix.plugin")
local core = require("apisix.core")
local router = require("apisix.router")
local get_service = require("apisix.http.service").get
local get_plugin_config = require("apisix.plugin_config").get
local gq_parse     = require("graphql").parse
local ngx_re         = require("ngx.re")
local ipairs = ipairs
local pcall = pcall
local os = os
local ngx  = ngx
local type = type
local tostring = tostring
local ngx_var = ngx.var
local ngx_md5 = ngx.md5

local plugin_name = "graphql-proxy-cache"

local STRATEGY_DISK = "disk"
local STRATEGY_MEMORY = "memory"

local schema = {
    type = "object",
    properties = {
        cache_zone = {
            type = "string",
            minLength = 1,
            maxLength = 100,
            default = "disk_cache_one",
        },
        cache_strategy = {
            type = "string",
            enum = {STRATEGY_DISK, STRATEGY_MEMORY},
            default = STRATEGY_DISK,
        },
        cache_ttl = {
            type = "integer",
            minimum = 1,
            default = 300,
        },
        consumer_isolation = {
            type = "boolean",
            default = true,
        },
        cache_set_cookie = {
            type = "boolean",
            default = false,
        },
    },
}


local _M = {
    version  = 0.1,
    priority = 1009,
    name     = plugin_name,
    schema   = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    local local_conf = core.config.local_conf()
    if local_conf.apisix.proxy_cache then
        for _, cache in ipairs(local_conf.apisix.proxy_cache.zones) do
            if cache.name == conf.cache_zone then
                return true
            end
        end

        return false, "cache_zone " .. conf.cache_zone .. " not found"
    end

    return true
end


local GRAPHQL_DEFAULT_MAX_SIZE       = 1048576               -- 1MiB
local GRAPHQL_REQ_QUERY              = "query"
local GRAPHQL_REQ_MIME_JSON          = "application/json"
local GRAPHQL_REQ_MIME_GRAPHQL       = "application/graphql"


local fetch_graphql_body = {
    ["GET"] = function(ctx, max_size)
        local body = ctx.var.args
        if not body or body == "" then
            return nil, "failed to read graphql data, args has zero size"
        end
        if #body > max_size then
            return nil, "failed to read graphql data, args size " .. #body
                        .. " is greater than the "
                        .. "maximum size " .. max_size .. " allowed"
        end

        return ctx.var.args
    end,

    ["POST"] = function(ctx, max_size)
        local body, err = core.request.get_body(max_size, ctx)
        if not body then
            return nil, "failed to read graphql data, " .. (err or "request body has zero size")
        end

        return body
    end
}


local check_graphql_request = {
    ["GET"] = function(ctx, body)
        local args, err = core.string.decode_args(body)
        if not args then
            return false, "invalid graphql request, args " .. err
        end

        local query = args[GRAPHQL_REQ_QUERY]
        if type(query) == "table" then
            query = query[1]
        end
        if not query then
            return false, "invalid graphql request, args[" ..
                        GRAPHQL_REQ_QUERY .. "] is nil"
        end
        return true, query
    end,

    ["POST"] = function(ctx, body)
        local content_type = core.request.header(ctx, "Content-Type") or ""
        if core.string.has_prefix(content_type, GRAPHQL_REQ_MIME_JSON) then
            local res, err = core.json.decode(body, {null_as_nil = true})
            if not res then
                return false, "invalid graphql request, " .. err
            end

            if not res[GRAPHQL_REQ_QUERY] then
                return false, "invalid graphql request, json body[" ..
                                GRAPHQL_REQ_QUERY .. "] is nil"
            end

            return true, res[GRAPHQL_REQ_QUERY]
        end

        if core.string.has_prefix(content_type, GRAPHQL_REQ_MIME_GRAPHQL) then
            return true, body
        end

        return false, "invalid graphql request, error content-type: " .. content_type
    end
}


local function graphql_cache_conf(ctx, conf)
    if ctx.graphql_cache_conf then
        return ctx.graphql_cache_conf
    end

    local cache_conf = {
        cache_strategy = conf.cache_strategy,
        cache_zone = conf.cache_zone,
        cache_method = {"GET", "POST"},
        cache_http_status = {200},
        cache_ttl = conf.cache_ttl,
        cache_set_cookie = conf.cache_set_cookie,
    }

    ctx.graphql_cache_conf = cache_conf

    return cache_conf
end


function _M.access(conf, ctx)
    local method = core.request.get_method()
    -- TODO: support PURGE method
    if method ~= "POST" and method ~= "GET" then
        return 405
    end

    local local_conf = core.config.local_conf()
    local max_size = GRAPHQL_DEFAULT_MAX_SIZE
    local size = core.table.try_read_attr(local_conf, "graphql", "max_size")
    if size then
        max_size = size
    end
    local body, err = fetch_graphql_body[method](ctx, max_size)
    if not body then
        core.log.error(err)
        return 400, {message = "Invalid graphql request: can't get graphql request body"}
    end

    local is_graphql_req, query_or_err = check_graphql_request[method](ctx, body)
    if not is_graphql_req then
        core.log.error(query_or_err)
        return 400, {message = query_or_err}
    end

    local ok, res = pcall(gq_parse, query_or_err)
    if not ok then
        core.log.error("failed to parse graphql: ", res)
        return 400, {message = "Invalid graphql request: failed to parse graphql query"}
    end

    local n = #res.definitions
    if n == 0 then
        core.log.error("failed to parse graphql: empty query")
        return 400, {message = "Invalid graphql request: empty graphql query"}
    end

    for i = 1, n do
        if res.definitions[i].operation == "mutation" then
            -- mutation operations are not cached
            ctx.var.upstream_cache_bypass = "1"
            ctx.var.upstream_no_cache = "1"
            core.response.set_header("Apisix-Cache-Status", "BYPASS")
            return
        end
    end

    core.log.debug("graphql-proxy-cache plugin access phase, body_size: ", #body)

    -- Bind the cache key to the route/service/host so two routes that share
    -- the same plugin config and receive the same query body do not collide.
    -- When consumer_isolation is on (default), prepend the authenticated
    -- identity so each consumer gets its own cache namespace. The control
    -- character separator is outside the charset permitted by the consumer
    -- username schema, keeping the components unambiguous.
    local route_id   = ctx.var.route_id   or ""
    local service_id = ctx.var.service_id or ""
    local host       = ctx.var.host       or ""

    local identity = ""
    if conf.consumer_isolation then
        identity = ctx.consumer_name
        if not identity or identity == "" then
            identity = ctx.var.remote_user or ""
        end
    end

    local conf_version = apisix_plugin.conf_version(conf)
    local value = ngx_md5(conf_version .. "\1" .. host .. "\1"
                          .. route_id .. "\1" .. service_id .. "\1"
                          .. identity .. "\1" .. body)
    ctx.var.upstream_cache_key = value

    core.response.set_header("APISIX-Cache-Key", value)

    core.log.debug("graphql-proxy-cache cache key value:", value)

    local handler
    if conf.cache_strategy == STRATEGY_MEMORY then
        handler = memory_handler
    else
        handler = disk_handler
    end

    return handler.access(graphql_cache_conf(ctx, conf), ctx)
end


function _M.header_filter(conf, ctx)
    if not ctx.var.upstream_cache_key or ctx.var.upstream_cache_key == "" then
        return
    end

    local cache_conf = graphql_cache_conf(ctx, conf)
    core.log.debug("graphql-proxy-cache plugin header filter phase, conf: ",
                    core.json.delay_encode(cache_conf))

    local handler
    if ctx.graphql_cache_conf.cache_strategy == STRATEGY_MEMORY then
        handler = memory_handler
    else
        handler = disk_handler
    end

    handler.header_filter(cache_conf, ctx)
end


function _M.body_filter(conf, ctx)
    if not ctx.var.upstream_cache_key or ctx.var.upstream_cache_key == "" then
        return
    end

    local cache_conf = graphql_cache_conf(ctx, conf)
    core.log.debug("graphql-proxy-cache plugin body filter phase, conf: ",
                        core.json.delay_encode(cache_conf))

    if ctx.graphql_cache_conf.cache_strategy == STRATEGY_MEMORY then
        memory_handler.body_filter(cache_conf, ctx)
    end
end


local function find_graphql_proxy_cache_conf(route_id)
    local routes = router.http_routes()
    if not routes then
        return nil
    end

    local route_value
    for _, route in ipairs(routes) do
        if type(route) == "table" and type(route.value) == "table"
            and tostring(route.value.id) == route_id then
            route_value = route.value
            break
        end
    end

    if not route_value then
        return nil
    end

    if route_value.plugins then
        return core.table.try_read_attr(route_value, "plugins", plugin_name)
    end

    if route_value.plugin_config_id then
        local plugin_config = get_plugin_config(route_value.plugin_config_id)
        return core.table.try_read_attr(plugin_config, "value", plugin_name)
    end

    if route_value.service_id then
        local service = get_service(route_value.service_id)
        return core.table.try_read_attr(service, "value", "plugins", plugin_name)
    end
    return nil
end


local function purge_hander()
    local uri_segs = core.utils.split_uri(ngx_var.uri)
    local strategy, route_id, cache_key = uri_segs[5], uri_segs[6], uri_segs[7]

    if strategy ~= STRATEGY_DISK and strategy ~= STRATEGY_MEMORY then
        core.log.error("invalid strategy in purge request: ", strategy)
        return core.response.exit(400)
    end

    if not route_id or route_id == "" or not cache_key or cache_key == "" then
        core.log.error("missing route_id or cache_key in purge request")
        return core.response.exit(400)
    end

    local conf = find_graphql_proxy_cache_conf(route_id)
    if not conf then
        core.log.error("failed to find graphql-proxy-cache conf, route_id: ", route_id)
        return core.response.exit(404)
    end

    if strategy ~= conf.cache_strategy then
        core.log.error("strategy mismatch: request strategy is ", strategy,
                       " but route is configured with ", conf.cache_strategy)
        return core.response.exit(400)
    end

    ngx_var.upstream_cache_key = cache_key

    if strategy == "disk" then
        ngx_var.upstream_cache_zone = conf.cache_zone
        local cache_zone_info = ngx_re.split(ngx_var.upstream_cache_zone_info, ",")

        local filename = util.generate_cache_filename(cache_zone_info[1], cache_zone_info[2],
            ngx.var.upstream_cache_key)

        if not util.file_exists(filename) then
            core.log.error("failed to purge graphql cache, file not exists: ", filename)
            return core.response.exit(404)
        end
        os.remove(filename)
    else
        local memory = memory_strategy({shdict_name = conf.cache_zone})
        -- Walk the Vary index and purge every variant, not just the legacy
        -- base-key entry, so PURGE clears all cached responses for the key.
        memory_handler.purge_all_variants(memory, ngx_var.upstream_cache_key)
    end

    return core.response.exit(200)
end


function _M.api()
    return {
        {
            methods = {"PURGE"},
            uri = "/apisix/plugin/graphql-proxy-cache/*",
            handler = purge_hander,
        }
    }
end


return _M
