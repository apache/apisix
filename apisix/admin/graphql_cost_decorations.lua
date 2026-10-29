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
--
-- Admin API for the GraphQL cost decorations consumed by graphql-limit-count.
--
-- A decoration is owned by a service and is only reachable through the service
-- scoped path, the same shape consumer credentials use:
--
--     /apisix/admin/services/{service_id}/graphql_cost_decorations
--     /apisix/admin/services/{service_id}/graphql_cost_decorations/{id}
--
-- Stored under the service it belongs to, `/services/{service_id}/graphql_cost_decorations/{id}`,
-- so it rides the services config watcher the way a credential rides the consumers
-- one. `apisix/http/service.lua` tells the two kinds of item apart by key. The
-- `service_id` field is written from the path as well, so the runtime can group by
-- service without re-parsing keys.
--
local core     = require("apisix.core")
local resource = require("apisix.admin.resource")

local ipairs   = ipairs
local type     = type
local tostring = tostring

local RESOURCE_NAME = "graphql_cost_decorations"

local base_get    = resource.get
local base_post   = resource.post
local base_put    = resource.put
local base_patch  = resource.patch
local base_delete = resource.delete


-- sub_path is "{service_id}/graphql_cost_decorations" or
-- "{service_id}/graphql_cost_decorations/{decoration_id}"
local function service_id_of(sub_path)
    local uri_segs = core.utils.split_uri(sub_path or "")
    return uri_segs[1]
end


local function check_conf(_id, conf, _need_id, schema)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    return true, nil
end


local function get_etcd_key(id, _conf, sub_path)
    local service_id = service_id_of(sub_path)
    if not service_id or service_id == "" then
        -- only reachable through the flat /apisix/admin/graphql_cost_decorations
        -- path, which this resource does not serve
        return nil
    end

    -- a sub resource of the service, the same layout consumer credentials use
    local key = "/services/" .. service_id .. "/" .. RESOURCE_NAME
    if id then
        key = key .. "/" .. id
    end

    return key
end


-- Rejects a field_path already decorated on the same service. Best effort: the
-- read and the following write are not atomic, so two concurrent writers can
-- still land a duplicate. The runtime resolves that deterministically (etcd key
-- order), it is only the configuration that becomes ambiguous.
local function check_duplicate_field_path(service_id, id, field_path)
    local res, err = core.etcd.get("/services/" .. service_id .. "/" .. RESOURCE_NAME,
                                   true)
    if not res then
        return 503, {error_msg = err}
    end

    if res.status ~= 200 or not res.body.list then
        return nil
    end

    for _, item in ipairs(res.body.list) do
        local value = item.value
        if type(value) == "table" and value.field_path == field_path
           and value.service_id == service_id
           and tostring(value.id) ~= tostring(id) then
            return 400, {error_msg = "field_path " .. field_path ..
                                     " is already decorated on this service by [" ..
                                     tostring(value.id) .. "]"}
        end
    end

    return nil
end


-- Verifies the service exists and stamps the ownership onto the stored value.
local function bind_service(conf, sub_path, id)
    local service_id = service_id_of(sub_path)
    if not service_id or service_id == "" then
        return 400, {error_msg = "missing service id"}
    end

    if type(conf) ~= "table" then
        return 400, {error_msg = "invalid configuration"}
    end

    if conf.service_id and tostring(conf.service_id) ~= tostring(service_id) then
        return 400, {error_msg = "wrong service_id, it is taken from the path"}
    end

    local res, err = core.etcd.get("/services/" .. service_id, false)
    if not res then
        return 503, {error_msg = err}
    end

    if res.status == 404 then
        return 404, {error_msg = "service not found"}
    end

    if res.status ~= 200 then
        return res.status, {error_msg = "failed to get the service"}
    end

    if conf.field_path then
        local code, dup_err = check_duplicate_field_path(service_id, id, conf.field_path)
        if code then
            return code, dup_err
        end
    end

    conf.service_id = service_id
    return nil
end


local _M = resource.new({
    name = RESOURCE_NAME,
    kind = "graphql cost decoration",
    schema = core.schema.graphql_cost_decoration,
    checker = check_conf,
    get_resource_etcd_key = get_etcd_key,
})


function _M:get(id, conf, sub_path)
    local service_id = service_id_of(sub_path)
    if not service_id or service_id == "" then
        return 400, {error_msg = "missing service id"}
    end

    local code, body = base_get(self, id, conf, sub_path)

    -- the range is now scoped by the service segment, so a sibling service cannot
    -- bleed in; the filter stays as the guard for a hand-written etcd key
    if code == 200 and not id and type(body) == "table" and body.list then
        local list = {}
        for _, item in ipairs(body.list) do
            if type(item.value) == "table"
               and tostring(item.value.service_id) == tostring(service_id) then
                core.table.insert(list, item)
            end
        end
        -- an empty dir already 404s in etcd; keep the same answer when the
        -- prefix range only turned up decorations of a different service
        if #list == 0 then
            return 404, {error_msg = "Key not found"}
        end

        body.list = list
        body.total = #list
    end

    return code, body
end


function _M:post(id, conf, sub_path, args)
    local code, err = bind_service(conf, sub_path, id)
    if code then
        return code, err
    end

    return base_post(self, id, conf, sub_path, args)
end


function _M:put(id, conf, sub_path, args)
    local code, err = bind_service(conf, sub_path, id)
    if code then
        return code, err
    end

    return base_put(self, id, conf, sub_path, args)
end


function _M:patch(id, conf, sub_path, args)
    if type(conf) ~= "table" then
        return 400, {error_msg = "invalid configuration"}
    end

    local service_id = service_id_of(sub_path)
    if not service_id or service_id == "" then
        return 400, {error_msg = "missing service id"}
    end

    if conf.service_id then
        return 400, {error_msg = "service_id can not be patched"}
    end

    -- a patch may move the decoration onto a field_path another one already owns
    if conf.field_path then
        local code, err = check_duplicate_field_path(service_id, id, conf.field_path)
        if code then
            return code, err
        end
    end

    return base_patch(self, id, conf, sub_path, args)
end


function _M:delete(id, conf, sub_path, uri_args)
    local service_id = service_id_of(sub_path)
    if not service_id or service_id == "" then
        return 400, {error_msg = "missing service id"}
    end

    return base_delete(self, id, conf, sub_path, uri_args)
end


return _M
