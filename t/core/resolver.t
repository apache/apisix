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
--- request
GET /t
--- response_body
ip_info: "127.0.0.1"
--- no_error_log
[error]



=== TEST 2: resolve host from dns
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local resolver = require("apisix.core.resolver")
            local domain = "apisix.apache.org"
            local ip_info, err = resolver.parse_domain(domain)
            if not ip_info then
                core.log.error("failed to parse domain: ", domain, ", error: ",err)
                return
            end
            ngx.say("ip_info: ", require("toolkit.json").encode(ip_info))
        }
    }
--- request
GET /t
--- response_body
ip_info: "151.101.2.132"
--- no_error_log
[error]



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
--- request
GET /t
--- error_log
failed to parse domain
