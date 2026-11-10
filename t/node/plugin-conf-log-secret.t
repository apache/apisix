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
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request && !$block->stream_request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log) {
        $block->set_value("no_error_log", "plaintext-redis-secret");
    }
});

run_tests;

__DATA__

=== TEST 1: stream route with a secret in its plugin conf, merged with a service
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1995": 1
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "service_id": "1",
                    "plugins": {
                        "limit-conn": {
                            "conn": 100,
                            "burst": 50,
                            "default_conn_delay": 0.1,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 1,
                            "redis_password": "plaintext-redis-secret",
                            "allow_degradation": true
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed
--- error_log
check stream plugin schema, name: limit-conn



=== TEST 2: load the stream route on start and hit it
--- stream_request
mmm
--- stream_response
hello world
--- error_log
check stream plugin schema, name: limit-conn
merge service [1] into stream route [1]
init plugin-level conf version



=== TEST 3: plugin checker fails on an unrelated field, watch update
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1', ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_password": "plaintext-redis-secret"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- the Admin API rejects an invalid plugin, so write it to etcd directly
            local res = assert(core.etcd.get("/routes/1"))
            local route = res.body.node.value
            route.plugins["response-rewrite"] = {status_code = 1}
            assert(core.etcd.set("/routes/1", route))
            ngx.sleep(1)
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
failed to check item data of [/apisix/routes] err:failed to check the configuration of plugin response-rewrite
key: /apisix/routes/1



=== TEST 4: plugin checker fails on an unrelated field, full load
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(1)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            code, body = t('/apisix/admin/services/1', ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
failed to check item data of [/apisix/routes] err:failed to check the configuration of plugin response-rewrite
key: /apisix/routes/1
