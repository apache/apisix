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
use Cwd qw(cwd);
use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();

my $apisix_home = $ENV{APISIX_HOME} // cwd();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $block_init = <<_EOC_;
    `ln -sf $apisix_home/apisix $apisix_home/t/servroot/apisix`;
_EOC_

    $block->set_value("init", $block_init);

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

add_test_cleanup_handler(sub {
    `rm -f $apisix_home/t/servroot/apisix`;
});

run_tests();

__DATA__

=== TEST 1: setup route by serverless
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/routes/pubsub", ngx.HTTP_PUT, {
                plugins = {
                    ["serverless-pre-function"] = {
                        phase = "access",
                        functions =  {
                            [[return function(conf, ctx)
                                local core = require("apisix.core");
                                local pubsub, err = core.pubsub.new()
                                if not pubsub then
                                    core.log.error("failed to initialize pubsub module, err: ", err)
                                    core.response.exit(400)
                                    return
                                end
                                pubsub:on("cmd_ping", function (params)
                                    if params.state == "test" then
                                        return {pong_resp = {state = "test"}}
                                    end
                                    return nil, "error"
                                end)
                                pubsub:wait()
                                ngx.exit(0)
                            end]],
                        }
                    }
                },
                uri = "/pubsub"
            })
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: hit route (with HTTP request)
--- request
GET /pubsub
--- error_code: 400
--- error_log
failed to initialize pubsub module, err: bad "upgrade" request header: nil



=== TEST 3: connect websocket service
--- config
    location /t {
        content_by_lua_block {
            local lib_pubsub = require("lib.pubsub")
            local test_pubsub = lib_pubsub.new_ws("ws://127.0.0.1:1984/pubsub")
            local data = test_pubsub:send_recv_ws_binary({
                sequence = 0,
                cmd_ping = {
                    state = "test"
                },
            })
            if data and data.pong_resp then
                ngx.say("ret: ", data.pong_resp.state)
            end
            test_pubsub:close_ws()
        }
    }
--- response_body
ret: test



=== TEST 4: connect websocket service (return error)
--- config
    location /t {
        content_by_lua_block {
            local lib_pubsub = require("lib.pubsub")
            local test_pubsub = lib_pubsub.new_ws("ws://127.0.0.1:1984/pubsub")
            local data = test_pubsub:send_recv_ws_binary({
                sequence = 0,
                cmd_ping = {
                    state = "non-test"
                },
            })
            if data and data.error_resp then
                ngx.say("ret: ", data.error_resp.message)
            end
            test_pubsub:close_ws()
        }
    }
--- response_body
ret: error



=== TEST 5: send unregistered command
--- config
    location /t {
        content_by_lua_block {
            local lib_pubsub = require("lib.pubsub")
            local test_pubsub = lib_pubsub.new_ws("ws://127.0.0.1:1984/pubsub")
            local data = test_pubsub:send_recv_ws_binary({
                sequence = 0,
                cmd_empty = {},
            })
            if data and data.error_resp then
                ngx.say(data.error_resp.message)
            end
            test_pubsub:close_ws()
        }
    }
--- response_body
unknown command
--- error_log
pubsub callback handler not registered for the command, command: cmd_empty



=== TEST 6: send text command (server skip command, keep connection)
--- config
    location /t {
        lua_check_client_abort on;
        content_by_lua_block {
            ngx.on_abort(function ()
                ngx.log(ngx.ERR, "text command is skipped, and close connection")
                ngx.exit(444)
            end)
            local lib_pubsub = require("lib.pubsub")
            local test_pubsub = lib_pubsub.new_ws("ws://127.0.0.1:1984/pubsub")
            test_pubsub:send_recv_ws_text("test")
            test_pubsub:close_ws()
        }
    }
--- abort
--- ignore_response
--- error_log
pubsub server receive non-binary data, type: text, data: test
text command is skipped, and close connection
fatal error in pubsub websocket server, err: failed to receive the first 2 bytes: closed



=== TEST 7: send wrong command: empty (server skip command, keep connection)
--- config
    location /t {
        lua_check_client_abort on;
        content_by_lua_block {
            ngx.on_abort(function ()
                ngx.log(ngx.ERR, "empty command is skipped, and close connection")
                ngx.exit(444)
            end)
            local lib_pubsub = require("lib.pubsub")
            local test_pubsub = lib_pubsub.new_ws("ws://127.0.0.1:1984/pubsub")
            test_pubsub:send_recv_ws_binary({})
            test_pubsub:close_ws()
        }
    }
--- abort
--- ignore_response
--- error_log
pubsub server receives empty command
empty command is skipped, and close connection
fatal error in pubsub websocket server, err: failed to receive the first 2 bytes: closed



=== TEST 8: send wrong command: undecodable (server skip command, keep connection)
--- config
    location /t {
        lua_check_client_abort on;
        content_by_lua_block {
            ngx.on_abort(function ()
                ngx.log(ngx.ERR, "empty command is skipped, and close connection")
                ngx.exit(444)
            end)
            local lib_pubsub = require("lib.pubsub")
            local test_pubsub = lib_pubsub.new_ws("ws://127.0.0.1:1984/pubsub")
            test_pubsub:send_recv_ws_binary("!@#$%^&*中文", true)
            test_pubsub:close_ws()
        }
    }
--- abort
--- ignore_response
--- error_log
pubsub server receives empty command
empty command is skipped, and close connection
fatal error in pubsub websocket server, err: failed to receive the first 2 bytes: closed
