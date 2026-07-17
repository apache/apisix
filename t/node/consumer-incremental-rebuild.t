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

=== TEST 1: key-auth route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": { "key-auth": {} },
                    "upstream": {
                        "nodes": { "127.0.0.1:1980": 1 },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
            )
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: create consumers alice and ghost (both present before the first request)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/consumers', ngx.HTTP_PUT,
                [[{ "username": "alice", "plugins": { "key-auth": { "key": "alice-key" } } }]])
            -- ghost is created here (before TEST 3's first auth request) and never
            -- updated, so its key_value map entry is produced by the initial full
            -- build, not by an incremental upsert. It is deleted in TEST 17 to prove
            -- the full-build path is also removable.
            local code = t('/apisix/admin/consumers', ngx.HTTP_PUT,
                [[{ "username": "ghost", "plugins": { "key-auth": { "key": "ghost-key" } } }]])
            if code >= 300 then ngx.status = code end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 3: bootstrap + create takes effect on next request (alice authenticates)
--- request
GET /hello
--- more_headers
apikey: alice-key
--- response_body
hello world
--- error_log
consumer plugin tree fully rebuilt



=== TEST 4: create a second consumer bob (incremental add, no full rebuild)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "bob",
                    "plugins": { "key-auth": { "key": "bob-key" } }
                }]]
            )
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 5: bob authenticates and alice still works
--- pipelined_requests eval
["GET /hello", "GET /hello"]
--- more_headers eval
["apikey: bob-key", "apikey: alice-key"]
--- response_body eval
["hello world\n", "hello world\n"]



=== TEST 6: update alice's key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "alice",
                    "plugins": { "key-auth": { "key": "alice-key-v2" } }
                }]]
            )
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 7: old key rejected after update
--- request
GET /hello
--- more_headers
apikey: alice-key
--- error_code: 401



=== TEST 8: new key accepted after update
--- request
GET /hello
--- more_headers
apikey: alice-key-v2
--- response_body
hello world



=== TEST 9: delete bob
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/bob', ngx.HTTP_DELETE)
            if code >= 300 then ngx.status = code end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 10: deleted consumer's key is rejected
--- request
GET /hello
--- more_headers
apikey: bob-key
--- error_code: 401



=== TEST 11: consumer with a credential + consumer group plugins still merge
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- consumer group carries a response-rewrite plugin
            local code = t('/apisix/admin/consumer_groups/cg1', ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "response-rewrite": { "headers": { "set": { "X-Group": "cg1" } } }
                    }
                }]])
            if code >= 300 then ngx.status = code; ngx.say("group"); return end

            -- consumer with NO direct plugins, in the group; key-auth lives on a credential
            code = t('/apisix/admin/consumers', ngx.HTTP_PUT,
                [[{ "username": "carol", "group_id": "cg1" }]])
            if code >= 300 then ngx.status = code; ngx.say("consumer"); return end

            code = t('/apisix/admin/consumers/carol/credentials/cred-1', ngx.HTTP_PUT,
                [[{ "plugins": { "key-auth": { "key": "carol-key" } } }]])
            if code >= 300 then ngx.status = code; ngx.say("credential"); return end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 12: credential authenticates and the consumer group plugin is applied
--- request
GET /hello
--- more_headers
apikey: carol-key
--- response_body
hello world
--- response_headers
X-Group: cg1



=== TEST 13: create a consumer that we will delete under concurrent creates
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/consumers', ngx.HTTP_PUT,
                [[{ "username": "victim", "plugins": { "key-auth": { "key": "victim-key" } } }]])
            if code >= 300 then ngx.status = code end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 14: victim authenticates
--- request
GET /hello
--- more_headers
apikey: victim-key
--- response_body
hello world



=== TEST 15: delete victim WHILE creating two consumers (net consumer count RISES)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- two creates + one delete in the same sync window: the total count
            -- goes up, so a delete detector keyed on "count decreased" would miss
            -- this. The delete must still take effect.
            t('/apisix/admin/consumers', ngx.HTTP_PUT,
                [[{ "username": "filler_a", "plugins": { "key-auth": { "key": "filler-a-key" } } }]])
            t('/apisix/admin/consumers', ngx.HTTP_PUT,
                [[{ "username": "filler_b", "plugins": { "key-auth": { "key": "filler-b-key" } } }]])
            local code = t('/apisix/admin/consumers/victim', ngx.HTTP_DELETE)
            if code >= 300 then ngx.status = code end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 16: victim key rejected immediately despite net-positive churn; fillers work
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- more_headers eval
["apikey: victim-key", "apikey: filler-a-key", "apikey: filler-b-key"]
--- error_code eval
[401, 200, 200]



=== TEST 17: delete ghost (a consumer built by the initial full build, never upserted)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/consumers/ghost', ngx.HTTP_DELETE)
            if code >= 300 then ngx.status = code end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 18: ghost's key is rejected (full-build entry was removed from the kv map)
--- request
GET /hello
--- more_headers
apikey: ghost-key
--- error_code: 401
