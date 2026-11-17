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
# What happens to an SSE session when the client goes away and comes back.
#
use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request && !$block->exec) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }

    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 11520;

        location /openapi.json {
            content_by_lua_block {
                local core = require("apisix.core")
                ngx.header["Content-Type"] = "application/json"
                ngx.say(core.json.encode({
                    openapi = "3.0.0",
                    info = { title = "Demo", version = "1.0.0" },
                    paths = { ["/pet"] = { get = { operationId = "getPet" } } },
                }))
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests;

__DATA__

=== TEST 1: a new session expires on its own after 30 minutes
--- config
    location /t {
        content_by_lua_block {
            local session = require("apisix.plugins.openapi-to-mcp.session")
            local id = assert(session.create())
            local dict = ngx.shared["mcp-session"]
            ngx.say("alive: ", tostring(session.exists(id)))
            ngx.say("ttl: ", dict:ttl("openapi-to-mcp:" .. id .. ":alive"))
        }
    }
--- response_body
alive: true
ttl: 1800



=== TEST 2: destroying a session takes its queue with it
--- config
    location /t {
        content_by_lua_block {
            local session = require("apisix.plugins.openapi-to-mcp.session")
            local id = assert(session.create())
            assert(session.push(id, "queued"))

            session.destroy(id)

            local dict = ngx.shared["mcp-session"]
            ngx.say("alive: ", tostring(dict:get("openapi-to-mcp:" .. id .. ":alive")))
            -- a shared dict list carries no TTL of its own, so a queue left
            -- behind would sit there until the dict runs out of room
            ngx.say("queue: ", tostring(dict:llen("openapi-to-mcp:" .. id .. ":queue")))
            ngx.say("exists: ", tostring(session.exists(id)))
        }
    }
--- response_body
alive: nil
queue: 0
exists: false



=== TEST 3: a message for a session that is gone is refused, not queued
--- config
    location /t {
        content_by_lua_block {
            local session = require("apisix.plugins.openapi-to-mcp.session")
            local id = assert(session.create())
            session.destroy(id)

            local ok, err = session.push(id, "late")
            ngx.say("push: ", tostring(ok), " ", tostring(err))
            -- nothing would ever drain a queue recreated here
            ngx.say("queue: ", tostring(ngx.shared["mcp-session"]:llen("openapi-to-mcp:" .. id .. ":queue")))
        }
    }
--- response_body
push: nil session is gone
queue: 0



=== TEST 4: a message that races the teardown leaves no queue behind
--- config
    location /t {
        content_by_lua_block {
            local session = require("apisix.plugins.openapi-to-mcp.session")
            local dict = ngx.shared["mcp-session"]
            local id = assert(session.create())

            -- the stream that drains the queue usually runs in another worker,
            -- so it can destroy the session between push's liveness check and
            -- its rpush. Reproduced by dropping the marker at exactly that
            -- point, which is what the other worker's destroy would do.
            local real_rpush = dict.rpush
            dict.rpush = function(self, key, value)
                local length = real_rpush(self, key, value)
                dict:delete("openapi-to-mcp:" .. id .. ":alive")
                return length
            end

            local ok, err = session.push(id, "racing")
            dict.rpush = real_rpush

            ngx.say("push: ", tostring(ok), " ", tostring(err))
            ngx.say("queue: ", tostring(dict:llen("openapi-to-mcp:" .. id .. ":queue")))
        }
    }
--- response_body
push: nil session is gone
queue: 0



=== TEST 5: an sse route to reconnect against
--- config
    location /t {
        content_by_lua_block {
            local ok = require("lib.openapi_to_mcp_fixture").put_routes({
                { 1, "/mcp-session-life", {
                    transport = "sse",
                    base_url = "http://127.0.0.1:11520",
                    openapi_url = "http://127.0.0.1:11520/openapi.json",
                } },
            })
            if ok then ngx.say("passed") end
        }
    }
--- response_body
passed



=== TEST 6: a message for a session the gateway never issued is refused
--- request
POST /mcp-session-life?sessionId=00000000-0000-4000-8000-000000000000
{"jsonrpc":"2.0","id":1,"method":"ping"}
--- more_headers
Content-Type: application/json
--- error_code: 404
--- response_body_like eval
qr/(?=.*"code":-32000)(?=.*"message":"Session not found for sessionId")(?=.*"id":null)/



=== TEST 7: reconnecting after a close gets a new session, and it works
--- timeout: 60
--- exec
python3 t/plugin/openapi_to_mcp_session_reconnect.py /mcp-session-life 2>&1
--- response_body
0 problem(s); the abandoned session answers 202



=== TEST 8: clean up
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            ngx.say("cleaned")
        }
    }
--- response_body
cleaned



=== TEST 9: a session is bound to the owner it was created for
--- config
    location /t {
        content_by_lua_block {
            local session = require("apisix.plugins.openapi-to-mcp.session")
            local id = assert(session.create("route-1\0alice"))
            ngx.say("same owner: ", tostring(session.exists(id, "route-1\0alice")))
            ngx.say("other route: ", tostring(session.exists(id, "route-2\0alice")))
            ngx.say("other consumer: ", tostring(session.exists(id, "route-1\0bob")))
            ngx.say("no owner: ", tostring(session.exists(id, nil)))
        }
    }
--- response_body
same owner: true
other route: false
other consumer: false
no owner: false



=== TEST 10: refreshing a session keeps its owner
--- config
    location /t {
        content_by_lua_block {
            local session = require("apisix.plugins.openapi-to-mcp.session")
            local id = assert(session.create("route-1\0alice"))
            ngx.say("touched: ", tostring(session.touch(id)))
            ngx.say("still bound: ", tostring(session.exists(id, "route-1\0alice")))
        }
    }
--- response_body
touched: true
still bound: true



=== TEST 11: the dict keys carry a prefix of their own
--- config
    location /t {
        content_by_lua_block {
            local session = require("apisix.plugins.openapi-to-mcp.session")
            local dict = ngx.shared["mcp-session"]
            local id = assert(session.create("route-1"))
            -- mcp-bridge stores <id>:queue in this same dict
            ngx.say("prefixed: ", tostring(dict:get("openapi-to-mcp:" .. id .. ":alive") ~= nil))
            ngx.say("bare key: ", tostring(dict:get(id .. ":alive")))
        }
    }
--- response_body
prefixed: true
bare key: nil
