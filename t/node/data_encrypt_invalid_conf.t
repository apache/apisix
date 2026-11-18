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
log_level("warn");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->yaml_config) {
        $block->set_value("yaml_config", <<_EOC_);
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
_EOC_
    }
});

run_tests;

__DATA__

=== TEST 1: consumer with an invalid plugin, watch update
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                            "key": "plaintext-consumer-key"
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
            local res = assert(core.etcd.get("/consumers/jack"))
            local consumer = res.body.node.value
            consumer.plugins["limit-count"] = {count = -1, time_window = 60}
            assert(core.etcd.set("/consumers/jack", consumer))
            ngx.sleep(1)
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
failed to check item data of [/apisix/consumers] err:failed to check the configuration of plugin limit-count
key: /apisix/consumers/jack
--- no_error_log
plaintext-consumer-key



=== TEST 2: consumer with an invalid plugin, cold start
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(1)
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
failed to check item data of [/apisix/consumers] err:failed to check the configuration of plugin limit-count
key: /apisix/consumers/jack
--- no_error_log
plaintext-consumer-key



=== TEST 3: route whose vars fail after its plugins pass, watch update
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/jack', ngx.HTTP_DELETE)
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
                        "csrf": {
                            "key": "plaintext-csrf-key"
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

            -- the Admin API rejects invalid vars, so write them to etcd directly
            local res = assert(core.etcd.get("/routes/1"))
            local route = res.body.node.value
            route.vars = {{"arg_k", "invalid-operator", "v"}}
            assert(core.etcd.set("/routes/1", route))
            ngx.sleep(1)
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
failed to check item data of [/apisix/routes] err:failed to validate the 'vars' expression
key: /apisix/routes/1
--- no_error_log
plaintext-csrf-key



=== TEST 4: route whose vars fail after its plugins pass, cold start
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
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
failed to check item data of [/apisix/routes] err:failed to validate the 'vars' expression
key: /apisix/routes/1
--- no_error_log
plaintext-csrf-key
