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
local get_routes = require("apisix.router").http_routes
local get_stream_routes = require("apisix.router").stream_routes
local apisix_upstream = require("apisix.upstream")
local resource = require("apisix.admin.resource")
local schema_plugin = require("apisix.admin.plugins").check_schema
local plugins_encrypt_conf = require("apisix.admin.plugins").encrypt_conf
local tostring = tostring
local ipairs = ipairs
local type = type
local loadstring = loadstring


local function check_conf(id, conf, need_id, schema, opts)
    opts = opts or {}
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    if need_id and not id then
        return nil, {error_msg = "wrong type of service id"}
    end

    local upstream_conf = conf.upstream
    if upstream_conf then
        local ok, err = apisix_upstream.check_upstream_conf(upstream_conf)
        if not ok then
            return nil, {error_msg = err}
        end
    end

    local upstream_id = conf.upstream_id
    if upstream_id and not opts.skip_references_check then
        local key = "/upstreams/" .. upstream_id
        local res, err = core.etcd.get(key)
        if not res then
            return nil, {error_msg = "failed to fetch upstream info by "
                                     .. "upstream id [" .. upstream_id .. "]: "
                                     .. err}
        end

        if res.status ~= 200 then
            return nil, {error_msg = "failed to fetch upstream info by "
                                     .. "upstream id [" .. upstream_id .. "], "
                                     .. "response code: " .. res.status}
        end
    end

    if conf.plugins then
        local ok, err = schema_plugin(conf.plugins)
        if not ok then
            return nil, {error_msg = err}
        end
    end

    if conf.script then
        local obj, err = loadstring(conf.script)
        if not obj then
            return nil, {error_msg = "failed to load 'script' string: "
                                     .. err}
        end

        if type(obj()) ~= "table" then
            return nil, {error_msg = "'script' should be a Lua object"}
        end
    end

    return true
end


local function delete_checker(id)
    local routes, routes_ver = get_routes()
    core.log.info("routes: ", core.json.delay_encode(routes, true))
    core.log.info("routes_ver: ", routes_ver)
    if routes_ver and routes then
        for _, route in ipairs(routes) do
            if type(route) == "table" and route.value
               and route.value.service_id
               and tostring(route.value.service_id) == id then
                return 400, {error_msg = "can not delete this service directly,"
                                         .. " route [" .. route.value.id
                                         .. "] is still using it now"}
            end
        end
    end

    local stream_routes, stream_routes_ver = get_stream_routes()
    core.log.info("stream_routes: ", core.json.delay_encode(stream_routes, true))
    core.log.info("stream_routes_ver: ", stream_routes_ver)
    if stream_routes_ver and stream_routes then
        for _, route in ipairs(stream_routes) do
            if type(route) == "table" and route.value
               and route.value.service_id
               and tostring(route.value.service_id) == id then
                return 400, {error_msg = "can not delete this service directly,"
                                         .. " stream_route [" .. route.value.id
                                         .. "] is still using it now"}
            end
        end
    end

    return nil, nil
end


local function encrypt_conf(id, conf)
    apisix_upstream.encrypt_conf(conf.upstream)
    plugins_encrypt_conf(conf.plugins)
end


local base_delete = resource.delete
local base_put    = resource.put


-- Creating a service under an id that was deleted earlier must not inherit the
-- cost model of its namesake: the delete path reclaims decorations only after the
-- service delete commits, so an rmdir that failed there leaves them behind, and
-- delete-then-recreate is exactly what declarative pipelines do. Reclaiming on
-- create makes that leftover inert for good.
--
-- Whether this is a create has to be decided before the write, but the reclaim
-- itself must happen after it: base_put still validates, so reclaiming first
-- would let a PUT that ends in 400 destroy the decorations on its way out.
local function service_absent(id)
    local res, err = core.etcd.get("/services/" .. id, false)
    if not res then
        return nil, {error_msg = err}
    end

    return res.status == 404
end


local function reclaim_stale_decorations(id)
    local res, err = core.etcd.rmdir("/services/" .. id .. "/graphql_cost_decorations/")
    if not res then
        core.log.error("failed to reclaim the stale graphql cost decorations of ",
                       "service [", id, "]: ", err)
    end
end

local _M = resource.new({
    name = "services",
    kind = "service",
    schema = core.schema.service,
    checker = check_conf,
    encrypt_conf = encrypt_conf,
    delete_checker = delete_checker,
})


function _M:put(id, conf, sub_path, args)
    local was_absent
    if id then
        local err
        was_absent, err = service_absent(id)
        if was_absent == nil then
            return 503, err
        end
    end

    local code, body = base_put(self, id, conf, sub_path, args)

    -- etcd answers 201 when the key was created, 200 when it was replaced
    if was_absent and code and code < 300 then
        reclaim_stale_decorations(id)
    end

    return code, body
end


function _M:delete(id, conf, sub_path, uri_args)
    local code, body = base_delete(self, id, conf, sub_path, uri_args)

    -- Reclaim the graphql cost decorations owned by the service: they live under
    -- their own etcd prefix, so etcd will not cascade for us.
    --
    -- Deliberately after the service is gone, and deliberately not fatal. The two
    -- prefixes cannot be deleted in one transaction, so one of the two orders has
    -- to lose:
    --   * reclaim first  -- a delete rejected afterwards (delete_checker races a
    --     route that starts referencing the service) leaves a *live* service with
    --     no cost model, silently charging 1 per query;
    --   * reclaim after  -- a failure here leaves decorations behind for a service
    --     that no longer exists. Nothing can route to it, so they are inert; they
    --     only resurface if the same service id is recreated, in which case
    --     inheriting the model is as often right as wrong.
    -- Losing configuration under a service that keeps serving traffic is the worse
    -- of the two, so the orphan is the accepted one.
    if code and code < 300 and id then
        local res, err = core.etcd.rmdir("/services/" .. id .. "/graphql_cost_decorations/")
        if not res then
            core.log.error("failed to delete the graphql cost decorations of service [",
                           id, "]: ", err)
        end
    end

    return code, body
end


return _M
