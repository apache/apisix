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
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    # SSE mock upstream: sends 3 events with a short delay between each,
    # then closes the connection.
    my $http_config = $block->http_config // <<_EOC_;
        server {
            listen 7760;
            default_type 'text/event-stream';

            location /events {
                content_by_lua_block {
                    ngx.header["Content-Type"] = "text/event-stream"
                    ngx.header["Cache-Control"] = "no-cache"
                    for i = 1, 3 do
                        ngx.print("data: event-" .. i .. "\\n\\n")
                        ngx.flush(true)
                        ngx.sleep(0.05)
                    end
                }
            }
        }
_EOC_
    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: schema check - valid config
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-buffering")
            local ok, err = plugin.check_schema({disable_proxy_buffering = true})
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: schema check - default value
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-buffering")
            local conf = {}
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
                return
            end
            if conf.disable_proxy_buffering ~= false then
                ngx.say("unexpected default: " .. tostring(conf.disable_proxy_buffering))
                return
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 3: schema check - invalid type
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-buffering")
            local ok, err = plugin.check_schema({disable_proxy_buffering = "yes"})
            if not ok then
                ngx.say("failed as expected")
                return
            end
            ngx.say("should not pass")
        }
    }
--- response_body
failed as expected



=== TEST 4: set up route with disable_proxy_buffering = true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/events",
                    "plugins": {
                        "proxy-buffering": {
                            "disable_proxy_buffering": true
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:7760": 1
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



=== TEST 5: SSE events are streamed through when disable_proxy_buffering = true
--- request
GET /events
--- more_headers
Accept: text/event-stream
--- response_body
data: event-1

data: event-2

data: event-3



=== TEST 6: set up route with disable_proxy_buffering = false (buffering enabled)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/events",
                    "plugins": {
                        "proxy-buffering": {
                            "disable_proxy_buffering": false
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:7760": 1
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



=== TEST 7: response is still delivered correctly when disable_proxy_buffering = false
--- request
GET /events
--- more_headers
Accept: text/event-stream
--- response_body
data: event-1

data: event-2

data: event-3
