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
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;
    my $config = $block->config // <<_EOC_;
    location /check {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()
            red:connect("127.0.0.1", 6379)
            red:flushall()
            
            -- make a request to /access
            local httpc = require("resty.http").new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/access"
            local res, err = httpc:request_uri(uri, {
                method = "GET"
            })
            
            if not res then
                ngx.say("failed to request: ", err)
                return
            end

            -- scan for limit_req keys
            -- key format: limit_req:remote_addr:excess or limit_req:remote_addr:last
            local keys, err = red:keys("limit_req:*")
            if not keys or #keys == 0 then
                ngx.say("no keys found")
                return
            end
            
            -- check ttl
            -- for rate=1, burst=10 -> ttl = ceil(10/1)+1 = 11.
            local ttl = red:ttl(keys[1])
            if ttl > 0 and ttl <= 11 then
                ngx.say("ttl is ok")
            else
                ngx.say("ttl is " .. tostring(ttl))
            end
        }
    }
_EOC_
    $block->set_value("config", $config);
});

run_tests;

__DATA__

=== TEST 1: trigger limit-req and check TTL
--- config
    location /test {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-req": {
                                "rate": 1,
                                "burst": 10,
                                "key": "remote_addr",
                                "policy": "redis",
                                "redis_host": "127.0.0.1",
                                "redis_port": 6379
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/access"
                }]]
                )
            ngx.say(body)
        }
    }
--- request
GET /test
--- response_body
passed



=== TEST 2: access and check ttl
--- request
GET /check
--- response_body
ttl is ok
