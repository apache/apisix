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

log_level('info');
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }

    my $config = ($block->config // "") . <<_EOC_;
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

_EOC_

    $block->set_value("config", $config);
});

run_tests();

__DATA__

=== TEST 1: set stream route(id: 1)
--- stream_enable
--- config
    location /test {
        content_by_lua_block {
            local core = require("apisix.core")
            local dkjson = require("dkjson")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1995": 1
                        },
                        "type": "roundrobin",
                        "checks": {
                            "active": {
                                "timeout": 40,
                                "type": "tcp",
                                "unhealthy": {
                                    "interval": 60,
                                    "failures": 2
                                },
                                "healthy": {
                                    "interval": 60,
                                    "successes": 2
                                },
                                "concurrency": 2
                            }
                        },
                        "retries": 3,
                        "timeout": {
                            "read": 40,
                            "send": 40,
                            "connect": 40
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return
            end

            local stream = t("/hit", ngx.HTTP_GET)
            if stream >= 300 then
                ngx.status = stream
                return
            end

            ngx.sleep(3)
            local healthcheck, _, body = t("/v1/healthcheck", ngx.HTTP_GET)
            if healthcheck >= 300 then
                ngx.status = healthcheck
                return
            end

            local healthcheck_data, err = core.json.decode(body)
            if not healthcheck_data then
                ngx.log(ngx.ERR, "failed to decode healthcheck data: ", err)
                return ngx.exit(503)
            end
            ngx.say(dkjson.encode(healthcheck_data))

            -- healthcheck of stream route
            local healthcheck, _, body = t("/v1/healthcheck/stream_routes/1", ngx.HTTP_GET)
            if healthcheck >= 300 then
                ngx.status = healthcheck
                return
            end

            local healthcheck_data, err = core.json.decode(body)
            if not healthcheck_data then
                ngx.log(ngx.ERR, "failed to decode healthcheck data: ", err)
                return ngx.exit(503)
            end
            ngx.say(dkjson.encode(healthcheck_data))
        }
    }
--- timeout: 5
--- request
GET /test
--- response_body
[{"name":"/apisix/stream_routes/1","nodes":[{"counter":{"http_failure":0,"success":0,"tcp_failure":0,"timeout_failure":0},"hostname":"127.0.0.1","ip":"127.0.0.1","port":1995,"status":"healthy"}],"type":"tcp"}]
{"name":"/apisix/stream_routes/1","nodes":[{"counter":{"http_failure":0,"success":0,"tcp_failure":0,"timeout_failure":0},"hostname":"127.0.0.1","ip":"127.0.0.1","port":1995,"status":"healthy"}],"type":"tcp"}
