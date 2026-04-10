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

BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();
log_level('info');


add_block_preprocessor(sub {
    my ($block) = @_;
    my $port = $ENV{TEST_NGINX_SERVER_PORT};

    my $config = $block->config // <<_EOC_;
    location /access_root_dir {
        content_by_lua_block {
            local httpc = require "resty.http"
            local hc = httpc:new()

            local res, err = hc:request_uri('http://127.0.0.1:$port/limit_conn', {
                headers = ngx.req.get_headers()
            })
            if res then
                ngx.exit(res.status)
            end
        }
    }

    location /test_concurrency {
        content_by_lua_block {
            local reqs = {}
            for i = 1, 10 do
                reqs[i] = { "/access_root_dir" }
            end
            local resps = { ngx.location.capture_multi(reqs) }
            for i, resp in ipairs(resps) do
                ngx.say(resp.status)
            end
        }
    }
_EOC_

    $block->set_value("config", $config);
});

run_tests;

__DATA__

=== TEST 1: use variable in conn and burst with default value
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-conn": {
                                "conn": "${http_conn ?? 5}",
                                "burst": "${http_burst ?? 2}",
                                "default_conn_delay": 0.1,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/limit_conn"
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



=== TEST 2: request without conn/burst headers
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
200
200
200
200
200
200
200
503
503
503



=== TEST 3: request with conn header
--- request
GET /test_concurrency
--- more_headers
conn: 3
--- timeout: 10s
--- response_body
200
200
200
200
200
503
503
503
503
503



=== TEST 4: request with conn and burst header
--- request
GET /test_concurrency
--- more_headers
conn: 3
burst: 4
--- timeout: 10s
--- response_body
200
200
200
200
200
200
200
503
503
503



=== TEST 5: configure conn/burst and rules at same time
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-conn": {
                                "conn": 2,
                                "burst": 1,
                                "default_conn_delay": 0.01,
                                "rejected_code": 503,
                                "key": "remote_addr",
                                "rules": [
                                    {
                                        "conn": 1,
                                        "burst": 0,
                                        "key": "${http_company}"
                                    }
                                ]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin limit-conn err: value should match only one schema, but matches both schemas 1 and 2"}



=== TEST 6: setup route with rules
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-conn": {
                                "default_conn_delay": 0.01,
                                "rejected_code": 503,
                                "rules": [
                                    {
                                        "conn": 4,
                                        "burst": 3,
                                        "key": "${http_user}"
                                    },
                                    {
                                        "conn": "${http_project_conn ?? 3}",
                                        "burst": "${http_project_burst ?? 2}",
                                        "key": "${http_project}"
                                    }
                                ]
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/limit_conn"
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



=== TEST 7: request matching user rule
--- request
GET /test_concurrency
--- more_headers
user: jack
--- timeout: 10s
--- response_body
200
200
200
200
200
200
200
503
503
503



=== TEST 8: request matching project rule with default conn/burst
--- request
GET /test_concurrency
--- more_headers
project: apisix
--- timeout: 10s
--- response_body
200
200
200
200
200
503
503
503
503
503



=== TEST 9: request matching project rule with custom conn/burst
--- request
GET /test_concurrency
--- more_headers
project: apisix
project-conn: 2
project-burst: 1
--- timeout: 10s
--- response_body
200
200
200
503
503
503
503
503
503
503



=== TEST 10: request not matching any rule
--- request
GET /test_concurrency
--- timeout: 10s
--- response_body
500
500
500
500
500
500
500
500
500
500
--- error_log
failed to get limit conn rules
