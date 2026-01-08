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
            local redis_cluster = require "resty.rediscluster"
            local serv_list = {
                { ip = "127.0.0.1", port = 5000 },
                { ip = "127.0.0.1", port = 5001 },
                { ip = "127.0.0.1", port = 5002 },
                { ip = "127.0.0.1", port = 5003 },
                { ip = "127.0.0.1", port = 5004 },
                { ip = "127.0.0.1", port = 5005 },
            }
            local config = {
                name = "test-cluster",
                serv_list = serv_list,
                keepalive_timeout = 60000,
                keepalive_cons = 1000,
                connect_timeout = 1000,
                socket_timeout = 1000,
                dict_name = "plugin-limit-req-redis-cluster-slot-lock",
            }

            -- Flush all keys in the cluster
            for _, node in ipairs(serv_list) do
                local red = redis:new()
                red:set_timeout(1000)
                local ok, err = red:connect(node.ip, node.port)
                if ok then
                    red:flushall()
                    red:close()
                end
            end

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

            local found_key
            for _, node in ipairs(serv_list) do
                local red_node = redis:new()
                red_node:set_timeout(1000)
                local ok, err = red_node:connect(node.ip, node.port)
                if ok then
                    local keys, err = red_node:keys("limit_req:limit_req_ttl_test_*")
                    if keys and #keys > 0 then
                        found_key = keys[1]
                        red_node:close()
                        break
                    end
                    red_node:close()
                end
            end

            if not found_key then
                 ngx.say("no keys found")
                 return
            end

            local ttl, err = red:ttl(found_key)
            
            if not ttl or ttl == -2 then
                 ngx.say("no keys found")
                 return
            end

            -- for rate=1, burst=10 -> ttl = ceil(10/1)+1 = 11.
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
                                "key": "limit_req_ttl_test_$remote_addr",
                                "key_type": "var_combination",
                                "policy": "redis-cluster",
                                "redis_cluster_nodes": [
                                    "127.0.0.1:5000",
                                    "127.0.0.1:5001",
                                    "127.0.0.1:5002",
                                    "127.0.0.1:5003",
                                    "127.0.0.1:5004",
                                    "127.0.0.1:5005"
                                ],
                                "redis_cluster_name": "redis-cluster-1"
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
