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

    if (!$block->yaml_config) {
        my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

        $block->set_value("yaml_config", $yaml_config);
    }

    if ($block->apisix_yaml) {
        my $upstream = <<_EOC_;
upstreams:
  - id: 1
    type: roundrobin
    nodes:
      "test.com:1980": 1
    checks:
      active:
        http_path: "/status"
        host: 127.0.0.1
        port: 1988
        healthy:
          interval: 1
          successes: 1
        unhealthy:
          interval: 1
          http_failures: 1
#END
_EOC_

        $block->set_value("apisix_yaml", $block->apisix_yaml . $upstream);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: healthchecker recreation with changing DNS resolution
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream:
        type: roundrobin
        nodes:
            "test.com:1980": 1
        checks:
            active:
                http_path: "/status"
                host: 127.0.0.1
                port: 1988
                healthy:
                    interval: 1
                    successes: 1
                unhealthy:
                    interval: 1
                    http_failures: 1
--- config
    location /t {
        content_by_lua_block {
            -- Counter to track DNS resolution calls
            local dns_call_count = 0

            -- Override the core.resolver.parse_domain function
            local core = require("apisix.core")
            local original_parse_domain = core.resolver.parse_domain
            core.resolver.parse_domain = function(domain)
                if domain == "test.com" then
                    dns_call_count = dns_call_count + 1
                    if dns_call_count == 1 then
                        return "127.0.0.1", nil
                    else
                        return "127.0.0.2", nil
                    end
                end
                return original_parse_domain(domain)
            end

            -- First request
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.say("First request status: ", res and res.status or err)

            -- Wait for healthchecker to be created
            ngx.sleep(2)

            -- Second request - should trigger DNS resolution again
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.say("Second request status: ", res and res.status or err)

            -- Wait for healthchecker recreation
            ngx.sleep(4)

            -- Restore original DNS function
            core.resolver.parse_domain = original_parse_domain
        }
    }
--- response_body
First request status: 200
Second request status: 200
--- error_log
create new checker
reused checker with incremental targets
--- timeout: 10



=== TEST 2: unhealthy node stays out of rotation across a DNS query failure
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream:
        type: roundrobin
        nodes:
          - host: test.com
            port: 1970
            weight: 1
            priority: 0
          - host: 127.0.0.1
            port: 1980
            weight: 1
            priority: -1
        checks:
            active:
                http_path: "/status"
                healthy:
                    interval: 1
                    successes: 1
                unhealthy:
                    interval: 1
                    tcp_failures: 1
                    http_failures: 1
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local original_parse_domain = core.resolver.parse_domain
            local dns_down = false
            core.resolver.parse_domain = function(domain)
                if domain == "test.com" then
                    if dns_down then
                        return nil, "failed to query the DNS server: timeout"
                    end
                    return "127.0.0.1"
                end
                return original_parse_domain(domain)
            end

            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local function hit(tag)
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
                ngx.say(tag, ": ", res and res.status or err)
            end

            -- creates the checker; nothing listens on 1970, so the primary is
            -- retried onto the fallback and then trips the active check
            hit("warm-up")
            ngx.sleep(3)
            hit("primary unhealthy")

            -- the primary must keep its address and its unhealthy state
            dns_down = true
            for i = 1, 3 do
                ngx.sleep(1.2)
                hit("dns down " .. i)
            end

            -- and must not come back as healthy once the name resolves again
            dns_down = false
            hit("dns restored 1")
            hit("dns restored 2")

            core.resolver.parse_domain = original_parse_domain
        }
    }
--- response_body
warm-up: 200
primary unhealthy: 200
dns down 1: 200
dns down 2: 200
dns down 3: 200
dns restored 1: 200
dns restored 2: 200
--- grep_error_log eval
qr/proxy request to 127\.0\.0\.1:19\d\d|keep the last resolved address: 127\.0\.0\.1|reused checker with incremental targets/
--- grep_error_log_out
proxy request to 127.0.0.1:1970
proxy request to 127.0.0.1:1980
proxy request to 127.0.0.1:1980
keep the last resolved address: 127.0.0.1
proxy request to 127.0.0.1:1980
keep the last resolved address: 127.0.0.1
proxy request to 127.0.0.1:1980
keep the last resolved address: 127.0.0.1
proxy request to 127.0.0.1:1980
proxy request to 127.0.0.1:1980
proxy request to 127.0.0.1:1980
--- timeout: 15
