#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
use t::APISIX 'no_plan';

no_root_location();
repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->http_config) {
        my $http_config = <<'_EOC_';
server {
    listen 127.0.0.1:8765;

    location /ping {
        return 200 '8765';
    }

    location /healthz {
        return 200 'ok';
    }
}

server {
    listen 127.0.0.2:8766;

    location /ping {
        return 200 '8766';
    }

    location /healthz {
        return 500;
    }
}
_EOC_
        $block->set_value("http_config", $http_config);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests;

__DATA__

=== TEST 1: enable metrics uri
--- timeout: 20
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")

            -- enable prometheus
            local metric_data = {
                uri = "/apisix/prometheus/metrics",
                plugins = {
                    ["public-api"] = {}
                }
            }

            local code, body = t.test('/apisix/admin/routes/metrics',
                ngx.HTTP_PUT, core.json.encode(metric_data))
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: the metrics remove one node after route has been updated(remove one node from upstream)
--- timeout: 20
--- config
    location /t {
        content_by_lua_block {
            local function extract_unique_ips(input)
                local filtered_ips = {}

                for ip in input:gmatch('node="([^"]+)"') do
                    if not filtered_ips[ip] then
                        filtered_ips[ip] = true
                    end
                end

                return filtered_ips
            end

            local t = require("lib.test_admin")
            local core = require("apisix.core")

            -- create a route
            local data = {
                uri = "/ping",
                    plugins = {
                        prometheus = {}
                    },
                upstream = {
                    nodes = {
                        ["127.0.0.1:8765"] = 1,
                        ["127.0.0.2:8766"] = 1
                    },
                    retries = 2
                }
            }
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT, core.json.encode(data))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local http = require("resty.http")

            --- send requst to upstream with 2 retries
            for i = 1, 2 do
                local httpc = http.new()
                local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ping"
                local _, _ = httpc:request_uri(uri, {method = "GET", keepalive = false})
                ngx.sleep(0.2)
            end

            --- get the metrics
            local httpc = http.new()
            local metric_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics"
            local metric_res, _ = httpc:request_uri(metric_uri, {method = "GET"})
            local ip_lists = extract_unique_ips(metric_res.body)
            ngx.say(core.json.encode(ip_lists, true))

            --- remove a node from upstream
            local data = {
                uri = "/ping",
                    plugins = {
                        prometheus = {}
                    },
                upstream = {
                    nodes = {
                        ["127.0.0.1:8765"] = 1
                    },
                    retries = 2
                }
            }
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT, core.json.encode(data))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            --- send requst to upstream with 2 retries
            for i = 1, 2 do
                local httpc = http.new()
                local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ping"
                local _, _ = httpc:request_uri(uri, {method = "GET", keepalive = false})
                ngx.sleep(0.2)
            end

            --- get the metrics
            local httpc = http.new()
            local metric_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics"
            local metric_res, _ = httpc:request_uri(metric_uri, {method = "GET"})
            local ip_lists = extract_unique_ips(metric_res.body)
            ngx.say(core.json.encode(ip_lists, true))
        }
    }
--- request
GET /t
--- response_body
{"127.0.0.1":true,"127.0.0.2":true}
{"127.0.0.1":true}



=== TEST 3: the metrics add one node after route has been updated(add one node from upstream)
--- timeout: 20
--- config
    location /t {
        content_by_lua_block {
            local function extract_unique_ips(input)
                local filtered_ips = {}

                for ip in input:gmatch('node="([^"]+)"') do
                    if not filtered_ips[ip] then
                        filtered_ips[ip] = true
                    end
                end

                return filtered_ips
            end

            local t = require("lib.test_admin")
            local core = require("apisix.core")

            -- create a route
            local data = {
                uri = "/ping",
                    plugins = {
                        prometheus = {}
                    },
                upstream = {
                    nodes = {
                        ["127.0.0.1:8765"] = 1
                    },
                    retries = 2
                }
            }
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT, core.json.encode(data))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local http = require("resty.http")

            --- send requst to upstream with 2 retries
            for i = 1, 2 do
                local httpc = http.new()
                local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ping"
                local _, _ = httpc:request_uri(uri, {method = "GET", keepalive = false})
                ngx.sleep(0.2)
            end

            --- get the metrics
            local httpc = http.new()
            local metric_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics"
            local metric_res, _ = httpc:request_uri(metric_uri, {method = "GET"})
            local ip_lists = extract_unique_ips(metric_res.body)
            ngx.say(core.json.encode(ip_lists, true))

            --- remove a node from upstream
            local data = {
                uri = "/ping",
                    plugins = {
                        prometheus = {}
                    },
                upstream = {
                    nodes = {
                        ["127.0.0.1:8765"] = 1,
                        ["127.0.0.2:8766"] = 1
                    },
                    retries = 2
                }
            }
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT, core.json.encode(data))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            --- send requst to upstream with 2 retries
            for i = 1, 2 do
                local httpc = http.new()
                local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ping"
                local _, _ = httpc:request_uri(uri, {method = "GET", keepalive = false})
                ngx.sleep(0.2)
            end

            --- get the metrics
            local httpc = http.new()
            local metric_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics"
            local metric_res, _ = httpc:request_uri(metric_uri, {method = "GET"})
            local ip_lists = extract_unique_ips(metric_res.body)
            ngx.say(core.json.encode(ip_lists, true))
        }
    }
--- request
GET /t
--- response_body
{"127.0.0.1":true}
{"127.0.0.1":true,"127.0.0.2":true}
