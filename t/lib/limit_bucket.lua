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
local http = require("resty.http")
local test = require("lib.test_admin").test
local limit_util = require("apisix.utils.limit")

local _M = {}

local function wait_for(predicate, description)
    for _ = 1, 1000 do
        if predicate() then
            return
        end
        ngx.sleep(0.01)
    end
    error("timed out waiting for " .. description)
end


function _M.new(name)
    local self = {name = name, route = "bucket-" .. name .. "-" .. ngx.worker.pid(), held = 0}

    function self:set(conf)
        if conf.policy == "redis-cluster" then
            conf.redis_cluster_nodes = {"127.0.0.1:5000", "127.0.0.1:5001"}
            conf.redis_cluster_name = "bucket-tests"
        elseif conf.policy == "redis-sentinel" then
            conf.redis_sentinels = {{host = "127.0.0.1", port = 26379}}
            conf.redis_master_name = "mymaster"
        end
        local code, body = test("/apisix/admin/routes/" .. self.route, ngx.HTTP_PUT,
            core.json.encode({
                uri = "/" .. self.route,
                plugins = {
                    [self.name] = conf,
                    ["proxy-rewrite"] = {uri = "/bucket_upstream"},
                },
                upstream = {type = "roundrobin", nodes = {
                    ["127.0.0.1:" .. ngx.var.server_port] = 1,
                }},
            }))
        assert(code == 200 or code == 201, body)
        local stored, err = core.etcd.get("/routes/" .. self.route)
        assert(stored, err)
        local saved = stored.body.node.value.plugins[self.name]
        assert(not (saved._meta and saved._meta.bucket_id), "runtime ID was persisted")
        local version = assert(stored.body.node.modifiedIndex)
        wait_for(function()
            local routes = require("apisix.router").http_routes()
            for _, route in ipairs(routes or {}) do
                if route.value and route.value.id == self.route then
                    return route.modifiedIndex == version
                end
            end
        end, "route revision " .. version)
        self.conf = core.table.deepcopy(conf)
        assert(require("apisix.plugins." .. self.name).check_schema(self.conf))
    end

    function self:key()
        return "/apisix/routes/" .. self.route .. ":" ..
               limit_util.get_bucket_id(self.conf) .. ":127.0.0.1"
    end

    function self:hit(args)
        local url = "http://127.0.0.1:" .. ngx.var.server_port .. "/" .. self.route
        if args then
            url = url .. "?" .. args
        end
        local res, err = http.new():request_uri(url)
        assert(res, err)
        return res
    end

    function self:hold(n)
        local threads, ids = {}, {}
        local signals = ngx.shared["plugin-limit-conn"]
        for i = 1, n do
            self.held = self.held + 1
            local id = self.route .. "-" .. self.held
            ids[i] = id
            threads[i] = ngx.thread.spawn(self.hit, self, "hold=" .. id)
            wait_for(function() return signals:get("held:" .. id) end, "held request " .. id)
        end
        return function()
            for i, id in ipairs(ids) do
                signals:set("release:" .. id, true, 20)
                local ok, res = ngx.thread.wait(threads[i])
                assert(ok and res.status == 200)
                signals:delete("held:" .. id)
                signals:delete("release:" .. id)
            end
        end
    end

    return self
end


return _M
