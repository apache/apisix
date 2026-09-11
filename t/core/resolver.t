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
no_long_string();
no_root_location();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests;

__DATA__

=== TEST 1: resolve host from /etc/hosts
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local resolver = require("apisix.core.resolver")
            local domain = "localhost"
            local ip_info, err = resolver.parse_domain(domain)
            if not ip_info then
                core.log.error("failed to parse domain: ", domain, ", error: ",err)
                return
            end
            ngx.say("ip_info: ", require("toolkit.json").encode(ip_info))
        }
    }
--- response_body
ip_info: "127.0.0.1"



=== TEST 2: resolve host from dns
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local resolver = require("apisix.core.resolver")
            local domain = "apisix.apache.org"
            resolver.parse_domain = function(domain) -- mock: resolver parser

                if domain == "apisix.apache.org" then
                    return {address = "127.0.0.2" }
                end
                error("unknown domain: " .. domain)
            end
            local ip_info, err = resolver.parse_domain(domain)
            if not ip_info then
                core.log.error("failed to parse domain: ", domain, ", error: ",err)
                return
            end
            ngx.say("ip_info: ", require("toolkit.json").encode(ip_info))
        }
    }
--- response_body
ip_info: {"address":"127.0.0.2"}



=== TEST 3: there is no mapping in /etc/hosts and dns
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local resolver = require("apisix.core.resolver")
            local domain = "abc1.test"
            resolver.parse_domain(domain)
        }
    }
--- error_log
failed to parse domain



=== TEST 4: test dns config with ipv6 enable
--- yaml_config
apisix:
  enable_ipv6: true
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local resolver = require("apisix.core.resolver")
            local domain = "localhost6"
            resolver.parse_domain = function(domain)  -- mock: resolver parse_domain
                 if domain == "localhost6" then
                    return {address = "::1" }
                 end
                 error("unknown domain: " .. domain)

            end
            local ip_info, err = resolver.parse_domain(domain)
            if not ip_info then
                core.log.error("failed to parse domain: ", domain, ", error: ",err)
                return
            end
            ngx.say("ip_info: ", require("toolkit.json").encode(ip_info))
        }
    }
--- response_body
ip_info: {"address":"::1"}



=== TEST 5: test dns config with ipv6 disable
--- yaml_config
apisix:
  enable_ipv6: false
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local resolver = require("apisix.core.resolver")
            local domain = "localhost6"
            local ip_info, err = resolver.parse_domain(domain)
            if not ip_info then
                core.log.error("failed to parse domain: ", domain, ", error: ",err)
                return
            end
            ngx.say("ip_info: ", require("toolkit.json").encode(ip_info))
        }
    }
--- error_log
failed to parse domain



=== TEST 6: core.dns.client recovers the rcode from resty.dns.client's error
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local resolver = require("apisix.core.resolver")
            local utils = require("apisix.core.utils")
            -- creates the dns client (resolved from /etc/hosts, no network)
            assert(utils.dns_parse("localhost"))
            local lib = require("resty.dns.client")
            local original_resolve = lib.resolve
            local replies = {
                ["nxdomain.test"] = function()
                    return nil, "dns server error: 3 name error"
                end,
                ["servfail.test"] = function()
                    return nil, "dns server error: 2 server failure"
                end,
                ["timeout.test"] = function()
                    return nil, "dns lookup pool exceeded retries (1): timeout"
                end,
                ["cacheonly.test"] = function()
                    return {errcode = 100, errstr = "cache only lookup failed"}
                end,
            }
            lib.resolve = function(domain)  -- mock: resty.dns.client
                return replies[domain]()
            end

            for _, domain in ipairs({"nxdomain.test", "servfail.test", "timeout.test",
                                    "cacheonly.test"}) do
                local ip, err, rcode = resolver.parse_domain(domain)
                ngx.say(domain, ": ip=", ip, " rcode=", rcode, " err=", err)
            end
            lib.resolve = original_resolve
        }
    }
--- response_body
nxdomain.test: ip=nil rcode=3 err=failed to query the DNS server: dns server error: 3 name error
servfail.test: ip=nil rcode=2 err=failed to query the DNS server: dns server error: 2 server failure
timeout.test: ip=nil rcode=nil err=failed to query the DNS server: dns lookup pool exceeded retries (1): timeout
cacheonly.test: ip=nil rcode=100 err=server returned error code: 100: cache only lookup failed
--- error_log
failed to parse domain: nxdomain.test
failed to parse domain: servfail.test
failed to parse domain: timeout.test
failed to parse domain: cacheonly.test
