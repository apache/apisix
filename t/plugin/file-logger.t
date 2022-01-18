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

no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (! $block->request) {
        $block->set_value("request", "GET /t");
    }

    if (! $block->no_error_log && ! $block->error_log) {
        $block->set_value("no_error_log", "[error]");
    }
});


run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.file-logger")
            local ok, err = plugin.check_schema({
                path = "file.log"
                })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: path is missing check
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.file-logger")
            local ok, err = plugin.check_schema()
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- no_error_log
property "path" is required



=== TEST 3: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file.log"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
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



=== TEST 4: verify plugin
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, message = t("/hello", ngx.HTTP_GET)
            local fd, err = io.open("file.log", 'r')
            local msg

            if fd then
                msg = fd:read()
                fd:close()
            else
                fd:close()
                core.log.error("failed to open file: logs/file.log, error info: ", err)
            end
            core.log.warn('msg: ', msg)

            if msg then
                ngx.status = code
                ngx.say('write log success')
            end
        }
    }
--- response_body
write log success
