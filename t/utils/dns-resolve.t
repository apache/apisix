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

log_level('debug');
repeat_each(1);
no_long_string();
no_root_location();
run_tests;

__DATA__

=== TEST 1: dns resolve
--- config
    location /t {
        content_by_lua_block {
            local dns_resolve = require("apisix").dns_resolve
            local ip1, err1 = dns_resolve("www.iresty.com")
            if not ip1 then
              ngx.say(err1)
            end
            local ip2, err2 = dns_resolve("www.iresty.com")
            if not ip2 then
              ngx.say(err2)
            end
            if ip1 == ip2 then
              ngx.say("OK")
            else
              ngx.say("Not OK")
            end
        }
    }
--- request
GET /t
--- response_body
OK

=== TEST 2: dns resolve ipv4
--- config
    location /t {
        content_by_lua_block {
            local dns_resolve = require("apisix").dns_resolve
            local domain = "127.0.0.1"
            local ip, err = dns_resolve(domain)
            if not ip then
              ngx.say(err)
            else
              ngx.say(ip)
            end
        }
    }
--- request
GET /t
--- response_body
127.0.0.1


=== TEST 2: dns resolve ipv6
--- config
    location /t {
        content_by_lua_block {
            local dns_resolve = require("apisix").dns_resolve
            local domain = "2001:0db8:86a3:08d3:1319:8a2e:0370:7344"
            local ip, err = dns_resolve(domain)
            if not ip then
              ngx.say(err)
            else
              ngx.say(ip)
            end
        }
    }
--- request
GET /t
--- response_body
2001:0db8:86a3:08d3:1319:8a2e:0370:7344
