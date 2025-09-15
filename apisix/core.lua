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
local log = require("apisix.core.log")
local utils = require("apisix.core.utils")
local table = require("apisix.core.table")
local string_sub = string.sub
local config_util = require("apisix.core.config_util")
local local_conf, err = require("apisix.core.config_local").local_conf()
if not local_conf then
    error("failed to parse yaml config: " .. err)
end

local config_provider = local_conf.deployment and local_conf.deployment.config_provider
                      or "etcd"
log.info("use config_provider: ", config_provider)

local config
-- Currently, we handle JSON parsing in config_yaml, so special processing is needed here.
if config_provider == "json" then
    config = require("apisix.core.config_yaml")
    config.file_type = "json"
else
    config = require("apisix.core.config_" .. config_provider)
end

config.type = config_provider

local function remove_etcd_prefix(key)
    local prefix = ""
    local local_conf =  require("apisix.core.config_local").local_conf()
    local role = table.try_read_attr(local_conf, "deployment", "role")
    local provider = table.try_read_attr(local_conf, "deployment", "role_" ..
    role, "config_provider")
    if provider == "etcd" and local_conf.etcd and local_conf.etcd.prefix then
        prefix = local_conf.etcd.prefix
    end
    return string_sub(key, #prefix + 1)
end

local function fetch_latest_conf(resource_path)
    -- if resource path contains json path, extract out the prefix
    -- for eg: extracts /routes/1 from /routes/1#plugins.abc
    resource_path = config_util.parse_path(resource_path)
    local resource_type, id
    -- Handle both formats:
    -- 1. /<etcd-prefix>/<resource_type>/<id>
    -- 2. /<resource_type>/<id>
    resource_path = remove_etcd_prefix(resource_path)
    resource_type, id = resource_path:match("^/([^/]+)/([^/]+)$")
    if not resource_type or not id then
        log.error("invalid resource path: ", resource_path)
        return nil
    end

    local key
    if resource_type == "upstreams" then
        key = "/upstreams"
    elseif resource_type == "routes" then
        key = "/routes"
    elseif resource_type == "services" then
        key = "/services"
    elseif resource_type == "stream_routes" then
        key = "/stream_routes"
    else
        log.error("unsupported resource type: ", resource_type)
        return nil
    end

    local data = config.fetch_created_obj(key)
    if not data then
        log.error("failed to fetch configuration for type: ", key)
        return nil
    end
    local resource = data:get(id)
    if not resource then
        -- this can happen if the resource was deleted
        -- after the this function was called so we don't throw error
        log.warn("resource not found: ", id, " in ", key,
                      "this can happen if the resource was deleted")
        return nil
    end

    return resource
end

local function get_nodes_ver(resource_path)
    local res_conf = fetch_latest_conf(resource_path)
    local upstream = res_conf.value.upstream or res_conf.value
    return upstream._nodes_ver
end


local function set_nodes_ver_and_nodes(resource_path, nodes_ver, nodes)
    local res_conf = fetch_latest_conf(resource_path)
    local upstream = res_conf.value.upstream or res_conf.value
    upstream._nodes_ver = nodes_ver
    upstream.nodes = nodes
end

return {
    version     = require("apisix.core.version"),
    log         = log,
    config      = config,
    config_util = config_util,
    sleep       = utils.sleep,
    fetch_latest_conf = fetch_latest_conf,
    get_nodes_ver = get_nodes_ver,
    set_nodes_ver_and_nodes = set_nodes_ver_and_nodes,
    json        = require("apisix.core.json"),
    table       = table,
    request     = require("apisix.core.request"),
    response    = require("apisix.core.response"),
    lrucache    = require("apisix.core.lrucache"),
    schema      = require("apisix.schema_def"),
    string      = require("apisix.core.string"),
    ctx         = require("apisix.core.ctx"),
    timer       = require("apisix.core.timer"),
    id          = require("apisix.core.id"),
    ip          = require("apisix.core.ip"),
    io          = require("apisix.core.io"),
    utils       = utils,
    dns_client  = require("apisix.core.dns.client"),
    etcd        = require("apisix.core.etcd"),
    tablepool   = require("tablepool"),
    resolver    = require("apisix.core.resolver"),
    os          = require("apisix.core.os"),
    pubsub      = require("apisix.core.pubsub"),
    math        = require("apisix.core.math"),
    event       = require("apisix.core.event"),
    env         = require("apisix.core.env"),
}
