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
log_level('debug');
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



=== TEST 2: to reduce one upstream node, the metric should also be reduced by one.
--- extra_init_worker_by_lua
    local healthcheck = require("resty.healthcheck")
    local new = healthcheck.new
    healthcheck.new = function(...)
        local obj = new(...)
        local clear = obj.delayed_clear
        obj.delayed_clear = obj.clear
        return obj
    end
--- timeout: 20
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")
            local http = require("resty.http")

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

            --- get the metrics
            local function get_metrics()
                local httpc = http.new()
                local metric_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics"
                local metric_res, err = httpc:request_uri(metric_uri, {method = "GET"})
                if err then
                    ngx.say("failed to request: ", err)
                    return
                end
                local apisix_upstream_status_body = find_apisix_upstream_status(metric_res.body)
                for _, match in ipairs(apisix_upstream_status_body) do
                    ngx.say(match)
                end
            end

            -- create a route
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

            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ping"
            local _, _ = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.sleep(3)

            --- get metrics
            get_metrics()

            ngx.say("update the upstream")

            --- update the route
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

            local http = require("resty.http")
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ping"
            local _, _ = httpc:request_uri(uri, {method = "GET", keepalive = false})

            --- get metrics
            get_metrics()
        }
    }
--- request
GET /t
--- grep_error_log eval
qr/create new checker: table: 0x|try to release checker: table: 0x|event: target added '127.0.0.1\(127.0.0.1:8767.*/
--- grep_error_log_out
create new checker: table: 0x
event: target added '127.0.0.1(127.0.0.1:8767)'
try to release checker: table: 0x
create new checker: table: 0x
--- response_body
apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8765"} 1
apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8766"} 0
apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8767"} 1
update the upstream
apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8765"} 1
apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8766"} 1



=== TEST 3: add an upstream node, and metric should also be added.
--- extra_init_worker_by_lua
    local healthcheck = require("resty.healthcheck")
    local new = healthcheck.new
    healthcheck.new = function(...)
        local obj = new(...)
        local clear = obj.delayed_clear
        obj.delayed_clear = obj.clear
        return obj
    end
--- timeout: 20
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")
            local http = require("resty.http")

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

            --- get the metrics
            local function get_metrics()
                local httpc = http.new()
                local metric_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics"
                local metric_res, err = httpc:request_uri(metric_uri, {method = "GET"})
                if err then
                    ngx.say("failed to request: ", err)
                    return
                end
                local apisix_upstream_status_body = find_apisix_upstream_status(metric_res.body)
                for _, match in ipairs(apisix_upstream_status_body) do
                    ngx.say(match)
                end
            end

            -- create a route
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

            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ping"
            local _, _ = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.sleep(3)

            --- get metrics
            get_metrics()

            ngx.say("update the upstream")

            --- update the route
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

            local http = require("resty.http")
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ping"
            local _, _ = httpc:request_uri(uri, {method = "GET", keepalive = false})

            --- get metrics
            get_metrics()
        }
    }
--- request
GET /t
--- grep_error_log eval
qr/create new checker: table: 0x|try to release checker: table: 0x|event: target added '127.0.0.1\(127.0.0.1:8767.*/
--- grep_error_log_out
create new checker: table: 0x
try to release checker: table: 0x
create new checker: table: 0x
event: target added '127.0.0.1(127.0.0.1:8767)'
--- response_body
apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8765"} 1
apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8766"} 0
update the upstream
apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8765"} 1
apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8766"} 1
apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8767"} 1



=== TEST 4: delete the route
--- extra_init_worker_by_lua
    local healthcheck = require("resty.healthcheck")
    local new = healthcheck.new
    healthcheck.new = function(...)
        local obj = new(...)
        local clear = obj.delayed_clear
        obj.delayed_clear = obj.clear
        return obj
    end
--- timeout: 20
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")
            local http = require("resty.http")

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

            --- get the metrics
            local function get_metrics()
                local httpc = http.new()
                local metric_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics"
                local metric_res, err = httpc:request_uri(metric_uri, {method = "GET"})
                if err then
                    ngx.say("failed to request: ", err)
                    return
                end
                local apisix_upstream_status_body = find_apisix_upstream_status(metric_res.body)
                for _, match in ipairs(apisix_upstream_status_body) do
                    ngx.say(match)
                end
            end

            -- create a route
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

            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ping"
            local _, _ = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.sleep(3)

            --- get metrics
            get_metrics()

            --- delete the route
            local code, body = t.test('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local http = require("resty.http")
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ping"
            local _, _ = httpc:request_uri(uri, {method = "GET", keepalive = false})

            --- get metrics
            get_metrics()
        }
    }
--- request
GET /t
--- grep_error_log eval
qr/create new checker: table: 0x|try to release checker: table: 0x/
--- grep_error_log_out
create new checker: table: 0x
try to release checker: table: 0x
--- response_body
apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8765"} 1
apisix_upstream_status{name="/apisix/routes/1",ip="127.0.0.1",port="8766"} 0
