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
    listen 8765 ssl;
    ssl_certificate ../../certs/mtls_server.crt;
    ssl_certificate_key ../../certs/mtls_server.key;
    ssl_client_certificate ../../certs/mtls_ca.crt;

    location /ping {
        return 200 '8765';
    }

    location /healthz {
        return 200 'ok';
    }
}

server {
    listen 8766 ssl;
    ssl_certificate ../../certs/mtls_server.crt;
    ssl_certificate_key ../../certs/mtls_server.key;
    ssl_client_certificate ../../certs/mtls_ca.crt;

    location /ping {
        return 200 '8766';
    }

    location /healthz {
        return 500;
    }
}


server {
    listen 8767 ssl;
    ssl_certificate ../../certs/mtls_server.crt;
    ssl_certificate_key ../../certs/mtls_server.key;
    ssl_client_certificate ../../certs/mtls_ca.crt;

    location /ping {
        return 200 '8766';
    }

    location /healthz {
        return 200 'ok';
    }
}

server {
    listen 8768 ssl;
    ssl_certificate ../../certs/mtls_server.crt;
    ssl_certificate_key ../../certs/mtls_server.key;
    ssl_client_certificate ../../certs/mtls_ca.crt;

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

=== TEST 1: https health check (two health nodes)
--- config
    location /t {
        lua_ssl_trusted_certificate ../../certs/mtls_ca.crt;
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local cert = t.read_file("t/certs/mtls_client.crt")
            local key =  t.read_file("t/certs/mtls_client.key")
            local data = {
                uri = "/ping",
                upstream = {
                    scheme = "https",
                    nodes = {
                        ["127.0.0.1:8765"] = 1,
                        ["127.0.0.1:8767"] = 1
                    },
                    tls = {
                        client_cert = cert,
                        client_key = key
                    },
                    retries = 2,
                    checks = {
                        active = {
                            type = "https",
                            http_path = "/healthz",
                            https_verify_certificate = false,
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
            ngx.sleep(0.5)

            local healthcheck_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/v1/healthcheck/routes/1"
            local httpc = http.new()
            local res, _ = httpc:request_uri(healthcheck_uri, {method = "GET", keepalive = false})
            local json_data = core.json.decode(res.body)
            assert(json_data.type == "https")
            assert(#json_data.nodes == 2)

            local function check_node_health(port, status)
                for _, node in ipairs(json_data.nodes) do
                    if node.port == port and node.status == status then
                        return true
                    end
                end
                return false
            end

            assert(check_node_health(8765, "healthy"), "Port 8765 is not healthy")
            assert(check_node_health(8767, "healthy"), "Port 8767 is not healthy")
        }
    }
--- request
GET /t
--- error_code: 200



=== TEST 2: https health check (one healthy node, one unhealthy node)
--- config
    location /t {
        lua_ssl_trusted_certificate ../../certs/mtls_ca.crt;
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local cert = t.read_file("t/certs/mtls_client.crt")
            local key =  t.read_file("t/certs/mtls_client.key")
            local data = {
                uri = "/ping",
                upstream = {
                    scheme = "https",
                    nodes = {
                        ["127.0.0.1:8765"] = 1,
                        ["127.0.0.1:8766"] = 1
                    },
                    tls = {
                        client_cert = cert,
                        client_key = key
                    },
                    retries = 2,
                    checks = {
                        active = {
                            type = "https",
                            http_path = "/healthz",
                            https_verify_certificate = false,
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
            for i = 1, 3 do
                local httpc = http.new()
                local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ping"
                local _, _ = httpc:request_uri(uri, {method = "GET", keepalive = false})
                ngx.sleep(0.5)
            end

            local healthcheck_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/v1/healthcheck/routes/1"
            local httpc = http.new()
            local res, _ = httpc:request_uri(healthcheck_uri, {method = "GET", keepalive = false})
            local json_data = core.json.decode(res.body)
            assert(json_data.type == "https")
            assert(#json_data.nodes == 2)

            local function check_node_health(port, status)
                for _, node in ipairs(json_data.nodes) do
                    if node.port == port and node.status == status then
                        return true
                    end
                end
                return false
            end

            assert(check_node_health(8765, "healthy"), "Port 8765 is not healthy")
            assert(check_node_health(8766, "unhealthy"), "Port 8766 is not unhealthy")
        }
    }
--- request
GET /t
--- grep_error_log eval
qr/\([^)]+\) unhealthy .* for '.*'/
--- grep_error_log_out
(upstream#/apisix/routes/1) unhealthy HTTP increment (1/1) for '127.0.0.1(127.0.0.1:8766)'



=== TEST 3: https health check (two unhealthy nodes)
--- config
    location /t {
        lua_ssl_trusted_certificate ../../certs/mtls_ca.crt;
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local cert = t.read_file("t/certs/mtls_client.crt")
            local key =  t.read_file("t/certs/mtls_client.key")
            local data = {
                uri = "/ping",
                upstream = {
                    scheme = "https",
                    nodes = {
                        ["127.0.0.1:8766"] = 1,
                        ["127.0.0.1:8768"] = 1
                    },
                    tls = {
                        client_cert = cert,
                        client_key = key
                    },
                    retries = 2,
                    checks = {
                        active = {
                            type = "https",
                            http_path = "/healthz",
                            https_verify_certificate = false,
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
            for i = 1, 3 do
                local httpc = http.new()
                local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ping"
                local _, _ = httpc:request_uri(uri, {method = "GET", keepalive = false})
                ngx.sleep(0.5)
            end

            local healthcheck_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/v1/healthcheck/routes/1"
            local httpc = http.new()
            local res, _ = httpc:request_uri(healthcheck_uri, {method = "GET", keepalive = false})
            local json_data = core.json.decode(res.body)
            assert(json_data.type == "https")
            assert(#json_data.nodes == 2)

            local function check_node_health(port, status)
                for _, node in ipairs(json_data.nodes) do
                    if node.port == port and node.status == status then
                        return true
                    end
                end
                return false
            end

            assert(check_node_health(8766, "unhealthy"), "Port 8766 is not unhealthy")
            assert(check_node_health(8768, "unhealthy"), "Port 8768 is not unhealthy")
        }
    }
--- request
GET /t
--- error_code: 200
