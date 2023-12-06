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
worker_connections(256);

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->yaml_config) {
        my $events_module = $ENV{TEST_EVENTS_MODULE} or "lua-resty-events";
        my $yaml_config = <<_EOC_;
apisix:
    events:
        module: "$events_module"
_EOC_

        $block->set_value("yaml_config", $yaml_config);
    }
});

run_tests();

__DATA__

=== TEST 1: set route(two healthy upstream nodes)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/server_port",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1981": 1
                        },
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 1,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 1,
                                    "http_failures": 2
                                }
                            }
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
--- request
GET /t
--- response_body
passed
--- grep_error_log eval
qr/^.*?\[error\](?!.*process exiting).*/
--- grep_error_log_out



=== TEST 2: In case of concurrency only one request can create a checker
--- config
    location /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")
            local test = healthcheck.new
            healthcheck.new = function(...)
                ngx.sleep(1)
                return test(...)
            end

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            local send_request = function()
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
                if not res then
                    ngx.log(ngx.ERR, err)
                    return
                end
            end

            local t = {}

            for i = 1, 10 do
                local th = assert(ngx.thread.spawn(send_request))
                table.insert(t, th)
            end

            for i, th in ipairs(t) do
                ngx.thread.wait(th)
            end

            ngx.exit(200)
        }
    }
--- request
GET /t
--- grep_error_log eval
qr/create new checker/
--- grep_error_log_out
create new checker
