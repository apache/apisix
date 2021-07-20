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
no_shuffle();
no_root_location();


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }

    my $config = $block->config // <<_EOC_;
    location /hit {
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 1985)
            if not ok then
                ngx.log(ngx.ERR, "failed to connect: ", err)
                return ngx.exit(503)
            end

            local bytes, err = sock:send("mmm")
            if not bytes then
                ngx.log(ngx.ERR, "send stream request error: ", err)
                return ngx.exit(503)
            end
            local data, err = sock:receive("*a")
            if not data then
                sock:close()
                return ngx.exit(503)
            end
            ngx.print(data)
        }
    }

    location /test_concurrency {
        content_by_lua_block {
            local reqs = {}
            for i = 1, 5 do
                reqs[i] = { "/hit" }
            end
            local resps = { ngx.location.capture_multi(reqs) }
            for i, resp in ipairs(resps) do
                ngx.say(resp.status)
            end
        }
    }
_EOC_

    $block->set_value("config", $config);

    my $stream_upstream_code = $block->stream_upstream_code // <<_EOC_;
            local sock = ngx.req.socket()
            local data = sock:receive("1")
            ngx.sleep(0.2)
            ngx.say("hello world")
_EOC_
    $block->set_value("stream_upstream_code", $stream_upstream_code);
});

run_tests;

__DATA__

=== TEST 1: set route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "nodes": {
                        "127.0.0.1:1995": 1
                    },
                    "type": "roundrobin"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/stream_routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-conn": {
                            "conn": 100,
                            "burst": 50,
                            "default_conn_delay": 0.1,
                            "key": "remote_addr"
                        }
                    },
                    "upstream_id": "1"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: not exceeding the burst
--- request
GET /test_concurrency
--- response_body
200
200
200
200
200
--- stream_enable



=== TEST 3: update route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-conn": {
                            "conn": 2,
                            "burst": 1,
                            "default_conn_delay": 0.1,
                            "key": "remote_addr"
                        }
                    },
                    "upstream_id": "1"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 4: exceeding the burst
--- request
GET /test_concurrency
--- response_body
200
200
200
503
503
--- error_log
Connection reset by peer
--- stream_enable
