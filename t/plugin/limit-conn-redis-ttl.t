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
            -- clear keys first
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
            
            local keys, err = red:keys("limit_conn:*")
            if not keys or #keys == 0 then
                ngx.say("no keys found")
                return
            end
            
            -- Key format: limit_conn:ip
            local ttl = red:ttl(keys[1])
            -- Expected 60
            if ttl > 50 and ttl <= 60 then
                ngx.say("ttl is 60")
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

=== TEST 1: check schema
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.limit-conn")
            local ok, err = plugin.check_schema({
                conn = 1,
                burst = 0,
                default_conn_delay = 0.1,
                rejected_code = 503,
                key = 'remote_addr',
                policy = "redis",
                redis_host = 'localhost',
                key_ttl = 10,
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok



=== TEST 2: trigger limit-conn and check default TTL
--- config
    location /test {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "conn": 100,
                                "burst": 50,
                                "default_conn_delay": 0.1,
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



=== TEST 3: access and check default ttl (should be 60)
--- request
GET /check
--- response_body
ttl is 60



=== TEST 4: configure custom TTL
--- config
    location /test_update {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "conn": 100,
                                "burst": 50,
                                "default_conn_delay": 0.1,
                                "key": "remote_addr",
                                "policy": "redis",
                                "redis_host": "127.0.0.1",
                                "redis_port": 6379,
                                "key_ttl": 10
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
GET /test_update
--- response_body
passed



=== TEST 5: access and check custom ttl (should be 10)
--- config
    location /check_custom {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()
            red:connect("127.0.0.1", 6379)
            red:flushall()
            
            local httpc = require("resty.http").new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/access"
            local res, err = httpc:request_uri(uri, {
                method = "GET"
            })
            
            local keys, err = red:keys("limit_conn:*")
            if not keys or #keys == 0 then
                ngx.say("no keys found")
                return
            end
            local ttl = red:ttl(keys[1])
            
            if ttl > 5 and ttl <= 10 then
                ngx.say("ttl is 10")
            else
                ngx.say("ttl is " .. tostring(ttl))
            end
        }
    }
--- request
GET /check_custom
--- response_body
ttl is 10
