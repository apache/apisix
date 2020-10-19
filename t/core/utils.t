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

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local get_seed = require("apisix.core.utils").get_seed_from_urandom

            ngx.say("random seed ", get_seed())
            ngx.say("twice: ", get_seed() == get_seed())
        }
    }
--- request
GET /t
--- response_body_like eval
qr/random seed \d+(\.\d+)?(e\+\d+)?\ntwice: false/



=== TEST 2: parse_addr
--- config
    location /t {
        content_by_lua_block {
            local parse_addr = require("apisix.core.utils").parse_addr
            local cases = {
                {addr = "127.0.0.1", host = "127.0.0.1", port = 80},
                {addr = "127.0.0.1:90", host = "127.0.0.1", port = 90},
                {addr = "www.test.com", host = "www.test.com", port = 80},
                {addr = "www.test.com:90", host = "www.test.com", port = 90},
                {addr = "[127.0.0.1:90", host = "[127.0.0.1:90", port = 80},
                {addr = "[::1]", host = "[::1]", port = 80},
                {addr = "[::1]:1234", host = "[::1]", port = 1234},
                {addr = "[::1234:1234]:12345", host = "[::1234:1234]", port = 12345},
            }
            for _, case in ipairs(cases) do
                local host, port = parse_addr(case.addr)
                assert(host == case.host, string.format("host %s mismatch %s", host, case.host))
                assert(port == case.port, string.format("port %s mismatch %s", port, case.port))
            end
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 3: specify resolvers
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local resolvers = {"8.8.8.8"}
            core.utils.set_resolver(resolvers)
            local ip_info, err = core.utils.dns_parse("github.com", resolvers)
            if not ip_info then
                core.log.error("failed to parse domain: ", host, ", error: ",err)
            end
            ngx.say(core.json.encode(ip_info))
        }
    }
--- request
GET /t
--- response_body eval
qr/"address":.+,"name":"github.com"/
--- no_error_log
[error]



=== TEST 4: default resolvers
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ip_info, err = core.utils.dns_parse("github.com")
            if not ip_info then
                core.log.error("failed to parse domain: ", host, ", error: ",err)
            end
            core.log.info("ip_info: ", core.json.encode(ip_info))
            ngx.say("resolvers: ", core.json.encode(core.utils.resolvers))
        }
    }
--- request
GET /t
--- response_body
resolvers: ["8.8.8.8","114.114.114.114"]
--- error_log eval
qr/"address":.+,"name":"github.com"/
--- no_error_log
[error]
