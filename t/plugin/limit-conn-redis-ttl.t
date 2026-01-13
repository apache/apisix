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
    my $extra_locs = <<_EOC_;
    location /slow_backend {
        content_by_lua_block {
            ngx.log(ngx.WARN, "hit slow_backend")
            ngx.sleep(2)
            ngx.say("ok")
        }
    }
_EOC_

    my $config = $block->config;
    if (defined $config) {
        $config .= $extra_locs;
        $block->set_value("config", $config);
    } else {
        $config = <<_EOC_;
    location /check {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()
            red:connect("127.0.0.1", 6379)
            -- clear keys first
            red:flushall()

            local function do_request()
                local httpc = require("resty.http").new()
                local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/access"
                local res, err = httpc:request_uri(uri, {
                    method = "GET"
                })
                if not res then
                    ngx.log(ngx.ERR, "failed to request: ", err)
                else
                    ngx.log(ngx.WARN, "request finished with status: ", res.status)
                end
            end

            local co = ngx.thread.spawn(do_request)
            ngx.sleep(0.5) -- wait for request to hit upstream

            local keys, err = red:keys("limit_conn:limit_conn_ttl_test_127.0.0.1*")
            if not keys or #keys == 0 then
                ngx.say("no keys found")
            else
                -- Key format: limit_conn:ip
                local ttl = red:ttl(keys[1])
                -- Expected default 3600
                if ttl > 3500 and ttl <= 3600 then
                    ngx.say("ttl is 3600")
                else
                    ngx.say("ttl is " .. tostring(ttl))
                end
            end
            
            ngx.thread.wait(co)
        }
    }
_EOC_
        $block->set_value("config", $config . $extra_locs);
    }
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
                key = 'limit_conn_ttl_test_$remote_addr',
                key_type = 'var_combination',
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
            local port = ngx.var.server_port
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/slow_backend"
                            },
                            "limit-conn": {
                                "conn": 100,
                                "burst": 50,
                                "default_conn_delay": 0.1,
                                "key": "limit_conn_ttl_test_$remote_addr",
                                "key_type": "var_combination",
                                "policy": "redis",
                                "redis_host": "127.0.0.1",
                                "redis_port": 6379
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:]] .. port .. [[": 1
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



=== TEST 3: access and check default ttl (should be 3600)
--- request
GET /check
--- response_body
ttl is 3600



=== TEST 4: configure custom TTL
--- config
    location /test_update {
        content_by_lua_block {
            local port = ngx.var.server_port
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/slow_backend"
                            },
                            "limit-conn": {
                                "conn": 100,
                                "burst": 50,
                                "default_conn_delay": 0.1,
                                "key": "limit_conn_ttl_test_$remote_addr",
                                "key_type": "var_combination",
                                "policy": "redis",
                                "redis_host": "127.0.0.1",
                                "redis_port": 6379,
                                "key_ttl": 10
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:]] .. port .. [[": 1
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

            local function do_request()
                local httpc = require("resty.http").new()
                local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/access"
                local res, err = httpc:request_uri(uri, {
                    method = "GET"
                })
                if not res then
                    ngx.log(ngx.ERR, "failed to request: ", err)
                end
            end

            local co = ngx.thread.spawn(do_request)
            ngx.sleep(0.5) -- wait for request to hit upstream

            local keys, err = red:keys("limit_conn:limit_conn_ttl_test_127.0.0.1*")
            if not keys or #keys == 0 then
                ngx.say("no keys found")
            else
                local ttl = red:ttl(keys[1])
                if ttl > 5 and ttl <= 10 then
                    ngx.say("ttl is 10")
                else
                    ngx.say("ttl is " .. tostring(ttl))
                end
            end
            
            ngx.thread.wait(co)
        }
    }
--- request
GET /check_custom
--- response_body
ttl is 10
