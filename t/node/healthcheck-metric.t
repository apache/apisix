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
    listen 8765;

    location /ping {
        return 200 '8765';
    }

    location /healthz {
        return 200 'ok';
    }
}

server {
    listen 8766;

    location /ping {
        return 200 '8766';
    }

    location /healthz {
        return 500;
    }
}


server {
    listen 8767;
    location /ping {
        return 200 '8767';
    }

    location /healthz {
        return 200 'ok';
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

=== TEST 1: should add a new one when remove a node from the upstream
--- config
    location /t {
        content_by_lua_block {
            local function find_apisix_upstream_status(multiLineStr)
                local pattern = "(apisix_upstream_status{.-)$"
                local result = {}

                for line in multiLineStr:gmatch("[^\r\n]+") do
                    local match = line:match(pattern)
                    if match then
                        table.insert(result, match)
                    end
                end

                return result
            end

            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local data = {
                uri = "/ping",
                upstream = {
                    nodes = {
                        ["127.0.0.1:8765"] = 1,
                        ["127.0.0.1:8766"] = 1,
                        ["127.0.0.1:8767"] = 1
                    },
                    retries = 2,
                    checks = {
                        active = {
                            http_path = "/healthz",
                            healthy = {
                                interval = 1,
                                successes = 1
                            },
                            unhealthy = {
                                interval = 1,
                                http_failures = 1
                            },
                        }
                    }
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
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ping"
            local _, _ = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.sleep(3)

            local healthcheck_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/v1/healthcheck/routes/1"
            local httpc = http.new()
            local route_res, _ = httpc:request_uri(healthcheck_uri, {method = "GET", keepalive = false})
            local route_json_data = core.json.decode(route_res.body)
            --- get the metrics
            local metric_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics"
            local metric_res, _ = httpc:request_uri(metric_uri, {method = "GET"})
            local apisix_upstream_status_body = find_apisix_upstream_status(metric_res.body)
            for _, match in ipairs(apisix_upstream_status_body) do
                ngx.say("before: " .. match)
            end
            ngx.say("will remove a node for test metric")

            local new_data = {
                uri = "/ping",
                upstream = {
                    nodes = {
                        ["127.0.0.1:8765"] = 1,
                        ["127.0.0.1:8766"] = 1
                    },
                    retries = 2,
                    checks = {
                        active = {
                            http_path = "/healthz",
                            healthy = {
                                interval = 1,
                                successes = 1
                            },
                            unhealthy = {
                                interval = 1,
                                http_failures = 1
                            },
                        }
                    }
                }
            }
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT, core.json.encode(new_data))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(1.5)
            --- get the metrics again
            local metric_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics"
            local metric_res, _ = httpc:request_uri(metric_uri, {method = "GET"})
            local apisix_upstream_status_body = find_apisix_upstream_status(metric_res.body)
            for _, match in ipairs(apisix_upstream_status_body) do
                ngx.say("after: " .. match)
            end
        }
    }
--- request
GET /t
--- response_body
before: apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8765"} 1
before: apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8766"} 0
before: apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8767"} 1
will remove a node for test metric
after: apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8765"} 1
after: apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8766"} 0



=== TEST 2: should remove one metric when add a node from the upstream
--- config
    location /t {
        content_by_lua_block {
            local function find_apisix_upstream_status(multiLineStr)
                local pattern = "(apisix_upstream_status{.-)$"
                local result = {}

                for line in multiLineStr:gmatch("[^\r\n]+") do
                    local match = line:match(pattern)
                    if match then
                        table.insert(result, match)
                    end
                end

                return result
            end

            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local data = {
                uri = "/ping",
                upstream = {
                    nodes = {
                        ["127.0.0.1:8765"] = 1,
                        ["127.0.0.1:8766"] = 1
                    },
                    retries = 2,
                    checks = {
                        active = {
                            http_path = "/healthz",
                            healthy = {
                                interval = 1,
                                successes = 1
                            },
                            unhealthy = {
                                interval = 1,
                                http_failures = 1
                            },
                        }
                    }
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
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ping"
            local _, _ = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.sleep(3)

            local healthcheck_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/v1/healthcheck/routes/1"
            local httpc = http.new()
            local route_res, _ = httpc:request_uri(healthcheck_uri, {method = "GET", keepalive = false})
            local route_json_data = core.json.decode(route_res.body)
            --- get the metrics
            local metric_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics"
            local metric_res, _ = httpc:request_uri(metric_uri, {method = "GET"})
            local apisix_upstream_status_body = find_apisix_upstream_status(metric_res.body)
            for _, match in ipairs(apisix_upstream_status_body) do
                ngx.say("before: " .. match)
            end
            ngx.say("will add a node for test metric")

            local new_data = {
                uri = "/ping",
                upstream = {
                    nodes = {
                        ["127.0.0.1:8765"] = 1,
                        ["127.0.0.1:8766"] = 1,
                        ["127.0.0.1:8767"] = 1
                    },
                    retries = 2,
                    checks = {
                        active = {
                            http_path = "/healthz",
                            healthy = {
                                interval = 1,
                                successes = 1
                            },
                            unhealthy = {
                                interval = 1,
                                http_failures = 1
                            },
                        }
                    }
                }
            }
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT, core.json.encode(new_data))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(1.5)
            --- get the metrics again
            local metric_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics"
            local metric_res, _ = httpc:request_uri(metric_uri, {method = "GET"})
            local apisix_upstream_status_body = find_apisix_upstream_status(metric_res.body)
            for _, match in ipairs(apisix_upstream_status_body) do
                ngx.say("after: " .. match)
            end
        }
    }
--- request
GET /t
--- response_body
before: apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8765"} 1
before: apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8766"} 0
will add a node for test metric
after: apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8765"} 1
after: apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8766"} 0
after: apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8767"} 1



=== TEST 3: delete a route should remove the metric
--- timeout: 20
--- config
    location /t {
        content_by_lua_block {
            local function find_apisix_upstream_status(multiLineStr)
                local pattern = "(apisix_upstream_status{.-)$"
                local result = {}

                for line in multiLineStr:gmatch("[^\r\n]+") do
                    local match = line:match(pattern)
                    if match then
                        table.insert(result, match)
                    end
                end

                return result
            end

            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local data = {
                uri = "/ping",
                upstream = {
                    nodes = {
                        ["127.0.0.1:8765"] = 1,
                        ["127.0.0.1:8766"] = 1
                    },
                    retries = 2,
                    checks = {
                        active = {
                            http_path = "/healthz",
                            healthy = {
                                interval = 1,
                                successes = 1
                            },
                            unhealthy = {
                                interval = 1,
                                http_failures = 1
                            },
                        }
                    }
                }
            }
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT, core.json.encode(data))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            --- active the healthcheck checker
            local http = require("resty.http")
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ping"
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            if not res then
                ngx.say("failed to request: ", err)
                return
            end
            ngx.sleep(1.5)

            --- get the metrics
            local metric_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics"
            local httpc = http.new()
            local metric_res, err = httpc:request_uri(metric_uri, {method = "GET"})
            if err then
                ngx.say("failed to request: ", err)
                return
            end
            local apisix_upstream_status_body = find_apisix_upstream_status(metric_res.body)
            for _, match in ipairs(apisix_upstream_status_body) do
                ngx.say("before: " .. match)
            end

            --- delete the route
            ngx.say("delete route 1")

            --- why 3.5? because the checker:delayed_clear(3)
            ngx.sleep(3.5)
            local metric_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics"
            local httpc = http.new()
            local metric_res, err = httpc:request_uri(metric_uri, {method = "GET"})
            if err then
                ngx.say("failed to request: ", err)
                return
            end
            local apisix_upstream_status_body = find_apisix_upstream_status(metric_res.body)
            for _, match in ipairs(apisix_upstream_status_body) do
                ngx.say("after: " .. match)
            end
        }
    }
--- request
GET /t
--- response_body
before: apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8765"} 1
before: apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8766"} 0
delete route 1
