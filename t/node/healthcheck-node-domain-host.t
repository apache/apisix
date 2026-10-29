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

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->http_config) {
        # probe targets that log what the active health checker actually sends:
        # the Host header over HTTP, and the TLS SNI over HTTPS.
        my $http_config = <<'_EOC_';
server {
    listen 1988;
    location /healthz {
        content_by_lua_block {
            ngx.log(ngx.WARN, "probe Host: ", ngx.var.http_host)
            ngx.say("ok")
        }
    }
}

server {
    listen 1989 ssl;
    ssl_certificate ../../certs/apisix.crt;
    ssl_certificate_key ../../certs/apisix.key;
    location /healthz {
        content_by_lua_block {
            ngx.log(ngx.WARN, "probe SNI: ", ngx.var.ssl_server_name)
            ngx.say("ok")
        }
    }
}
_EOC_
        $block->set_value("http_config", $http_config);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: domain node with the default pass_host is probed with the node domain as Host
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local original_parse_domain = core.resolver.parse_domain
            core.resolver.parse_domain = function(domain)
                if domain == "test.com" then
                    return "127.0.0.1", nil
                end
                return original_parse_domain(domain)
            end

            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "nodes": { "test.com:1988": 1 },
                    "checks": {
                        "active": {
                            "http_path": "/healthz",
                            "healthy": { "interval": 1, "successes": 1 },
                            "unhealthy": { "interval": 1, "http_failures": 1 }
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end

            code = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{ "uri": "/hello", "upstream_id": "1" }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end

            local http = require "resty.http"
            local httpc = http.new()
            httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/hello",
                              {method = "GET", keepalive = false})

            ngx.sleep(2)

            core.resolver.parse_domain = original_parse_domain
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
probe Host: test.com
--- no_error_log
probe Host: 127.0.0.1
--- timeout: 5



=== TEST 2: over HTTPS, the domain node is probed with the node domain as SNI (not the resolved ip)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local original_parse_domain = core.resolver.parse_domain
            core.resolver.parse_domain = function(domain)
                if domain == "test.com" then
                    return "127.0.0.1", nil
                end
                return original_parse_domain(domain)
            end

            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "scheme": "https",
                    "nodes": { "test.com:1989": 1 },
                    "checks": {
                        "active": {
                            "type": "https",
                            "http_path": "/healthz",
                            "https_verify_certificate": false,
                            "healthy": { "interval": 1, "successes": 1 },
                            "unhealthy": { "interval": 1, "http_failures": 1 }
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end

            code = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{ "uri": "/hello", "upstream_id": "1" }]]
            )
            if code >= 300 then
                ngx.status = code
                return
            end

            local http = require "resty.http"
            local httpc = http.new()
            httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/hello",
                              {method = "GET", keepalive = false})

            ngx.sleep(2)

            core.resolver.parse_domain = original_parse_domain
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
probe SNI: test.com
--- no_error_log
probe SNI: 127.0.0.1
--- timeout: 5
