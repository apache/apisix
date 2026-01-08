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
            local redis_cluster = require "resty.rediscluster"
            local config = {
                name = "test-cluster",
                serv_list = {
                    { ip = "127.0.0.1", port = 5000 },
                    { ip = "127.0.0.1", port = 5001 },
                    { ip = "127.0.0.1", port = 5002 },
                    { ip = "127.0.0.1", port = 5003 },
                    { ip = "127.0.0.1", port = 5004 },
                    { ip = "127.0.0.1", port = 5005 },
                },
                keepalive_timeout = 60000,
                keepalive_cons = 1000,
                connect_timeout = 1000,
                socket_timeout = 1000
            }
            local red = redis_cluster:new(config)
            
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
            
            local key = "limit_conn:127.0.0.1"
            local ttl, err = red:ttl(key)
            
            if not ttl then
                 ngx.say("failed to get ttl: ", err)
                 return
            end

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
                policy = "redis-cluster",
                redis_cluster_nodes = {
                    "127.0.0.1:5000",
                    "127.0.0.1:5001"
                },
                redis_cluster_name = "test",
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
                                "policy": "redis-cluster",
                                "redis_cluster_nodes": [
                                    "127.0.0.1:5000",
                                    "127.0.0.1:5001",
                                    "127.0.0.1:5002",
                                    "127.0.0.1:5003",
                                    "127.0.0.1:5004",
                                    "127.0.0.1:5005"
                                ],
                                "redis_cluster_name": "test-cluster"
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
                                "policy": "redis-cluster",
                                "redis_cluster_nodes": [
                                    "127.0.0.1:5000",
                                    "127.0.0.1:5001",
                                    "127.0.0.1:5002",
                                    "127.0.0.1:5003",
                                    "127.0.0.1:5004",
                                    "127.0.0.1:5005"
                                ],
                                "redis_cluster_name": "test-cluster",
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
            local redis_cluster = require "resty.rediscluster"
            local config = {
                name = "test-cluster",
                serv_list = {
                    { ip = "127.0.0.1", port = 5000 },
                    { ip = "127.0.0.1", port = 5001 },
                    { ip = "127.0.0.1", port = 5002 },
                    { ip = "127.0.0.1", port = 5003 },
                    { ip = "127.0.0.1", port = 5004 },
                    { ip = "127.0.0.1", port = 5005 },
                },
                keepalive_timeout = 60000,
                keepalive_cons = 1000,
                connect_timeout = 1000,
                socket_timeout = 1000
            }
            local red = redis_cluster:new(config)
            
            local httpc = require("resty.http").new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/access"
            local res, err = httpc:request_uri(uri, {
                method = "GET"
            })
            
            local key = "limit_conn:127.0.0.1"
            local ttl, err = red:ttl(key)
            
            if not ttl then
                 ngx.say("failed to get ttl: ", err)
                 return
            end
            
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
