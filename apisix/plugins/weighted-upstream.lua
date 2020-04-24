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
local balancer = require("ngx.balancer")
local roundrobin  = require("resty.roundrobin")

local schema = {
    type = "object",
    properties = {
        total_weight = {
            type = "integer",
            minimum = 0
        },
        upstream_ids = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    upstream_id = {type = "integer"},
                    weight = {type = "integer", minimum = 0}
                },
                required = {"upstream_id","weight"}
            },
            minItems = 1
        }
    },
    required = {"upstream_ids"},
}


local plugin_name = "weighted-upstream"

local _M = {
    version = 0.1,
    priority = 4000,
    name = plugin_name,
    schema = schema,
}

local lrucache_upstream_picker = core.lrucache.new({
    ttl = 300, count = 256
})

local pick_upstream_server

function _M.init()
    core.log.info("plugin balancer init, plugin_name: ",plugin_name)
    pick_upstream_server = require("apisix.balancer").pick_upstream_server
end

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)

    if not ok then
        return false, err
    end

    -- Check whether upstream exists
    return true
end

local function create_upstream_picker(conf)

    local upstream_ids = core.table.new(#conf.upstream_ids,0)
    for _, upstream in ipairs(conf.upstream_ids) do
        upstream_ids[upstream.upstream_id] = upstream.weight
    end

    local picker = roundrobin:new(upstream_ids)
    return {
        conf = conf,
        get = function ()
            return picker:find()
        end
    }
end

function _M.balancer(conf, ctx)
    -- 
    local key = ctx.conf_type .. "#" .. ctx.conf_id
    local upstream_picker = lrucache_upstream_picker(key, ctx.conf_version,create_upstream_picker, conf)

    local up_id = upstream_picker.get()
    if not up_id then
        core.log.error("failed to pick upstream: ", err)
        return core.response.exit(502)
    end
    -- NOTE: update `ctx.balancer_name` is important, APISIX will skip other
    -- balancer handler.
    ctx.balancer_name = plugin_name

    core.log.info("plugin balancer: ", plugin_name, ", picked upstream: ", core.json.encode(up_id))
    
    local ip, port, err = pick_upstream_server(up_id, ctx)
    if err then
        core.log.error("failed to pick server: ", err)
        return core.response.exit(502)
    end

    local ok, err = balancer.set_current_peer(ip, port)
    if not ok then
        core.log.error("failed to set server peer: ", err)
        return core.response.exit(502)
    end
end


return _M
