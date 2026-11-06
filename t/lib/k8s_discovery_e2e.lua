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

-- helpers for t/kubernetes/discovery/kubernetes6.t: change the ns-a/ep
-- Endpoints through the kubectl proxy and send real requests through APISIX

local core = require("apisix.core")
local http = require("resty.http")
local ngx = ngx
local ipairs = ipairs
local tostring = tostring

local _M = {}

local apiserver = "http://127.0.0.1:6445"
local ep_path = "/api/v1/namespaces/ns-a/endpoints/ep"
local ep_collection = "/api/v1/namespaces/ns-a/endpoints"


function _M.new(gateway_port)
    local t = {}
    local gateway = "http://127.0.0.1:" .. tostring(gateway_port)

    local function k8s(method, path, body, content_type)
        local httpc = http.new()
        httpc:set_timeouts(5000, 5000, 5000)
        local res, err = httpc:request_uri(apiserver .. path, {
            method = method,
            body = body,
            headers = {["Content-Type"] = content_type or "application/json"},
        })
        if not res then
            return "err:" .. tostring(err)
        end
        return res.status
    end

    function t.port_subsets(port)
        return {{
            addresses = {{ip = "127.0.0.1"}},
            ports = {{name = "p1", port = port}},
        }}
    end

    -- the subsets kubernetes2.t installs, so later test files find them
    function t.fixture_subsets()
        return {
            {
                addresses = {{ip = "10.0.0.1"}, {ip = "10.0.0.2"}},
                ports = {{name = "p1", port = 5001}},
            },
            {
                addresses = {{ip = "20.0.0.1"}, {ip = "20.0.0.2"}},
                ports = {{name = "p2", port = 5002}},
            },
        }
    end

    function t.set_subsets(subsets)
        local patch
        if #subsets == 0 then
            patch = '[{"op":"replace","path":"/subsets","value":[]}]'
        else
            patch = core.json.encode({{op = "replace", path = "/subsets", value = subsets}}, true)
        end
        return k8s("PATCH", ep_path, patch, "application/json-patch+json")
    end

    function t.delete_endpoints()
        return k8s("DELETE", ep_path)
    end

    function t.create_endpoints(subsets)
        local body = core.json.encode({
            apiVersion = "v1",
            kind = "Endpoints",
            metadata = {name = "ep", namespace = "ns-a"},
            subsets = subsets,
        }, true)
        return k8s("POST", ep_collection, body)
    end

    -- one request on a fresh connection, so that different requests can be
    -- served by different workers; returns the body on 200, else the status
    function t.get(path)
        local httpc = http.new()
        -- a probe proxied to a stale, unroutable address must fail fast
        httpc:set_timeouts(2000, 2000, 2000)
        local res, err = httpc:request_uri(gateway .. path, {keepalive = false})
        if not res then
            return "err:" .. tostring(err)
        end
        if res.status ~= 200 then
            return tostring(res.status)
        end
        return res.body
    end

    local function probe()
        return t.get("/server_port")
    end

    -- polls until n consecutive answers equal expected; returns the seconds
    -- it took (nil on timeout) and how many answers were outside allowed
    function t.wait_for(expected, n, timeout, allowed)
        ngx.update_time()
        local start = ngx.now()
        local unexpected = 0
        while true do
            local ok = true
            for _ = 1, n do
                local got = probe()
                if allowed and not allowed[got] then
                    unexpected = unexpected + 1
                end
                if got ~= expected then
                    ok = false
                    break
                end
            end
            ngx.update_time()
            local elapsed = ngx.now() - start
            if ok then
                return elapsed, unexpected
            end
            if elapsed > timeout then
                return nil, unexpected
            end
            ngx.sleep(0.2)
        end
    end

    function t.count_other_than(expected, n)
        local other = 0
        for _ = 1, n do
            if probe() ~= expected then
                other = other + 1
            end
        end
        return other
    end

    -- the names in the discovery dump, as a set
    function t.dump_names()
        local names = {}
        local data = require("apisix.discovery.kubernetes").dump_data()
        for _, cluster in ipairs(data.endpoints or {}) do
            for _, ep in ipairs(cluster.endpoints or {}) do
                names[ep.name] = true
            end
        end
        return names
    end

    return t
end


return _M
