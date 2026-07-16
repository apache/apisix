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
no_root_location();
no_shuffle();
add_block_preprocessor(sub {
    my ($block) = @_;
    my $port = $ENV{TEST_NGINX_SERVER_PORT};
    my $config = $block->config // <<_EOC_;
    location /access_root_dir {
        content_by_lua_block {
            local httpc = require "resty.http"
            local hc = httpc:new()

            local res, err = hc:request_uri('http://127.0.0.1:$port/limit_conn')
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


    location /access_root_dir2 {
        content_by_lua_block {
            local httpc = require "resty.http"
            local hc = httpc:new()

            local res, err = hc:request_uri('http://127.0.0.1:$port/limit_conn2')
            if res then
                ngx.exit(res.status)
            end
        }
    }

    location /test_concurrency2 {
        content_by_lua_block {
            local reqs = {}
            for i = 1, 10 do
                if i % 2 == 0 then
                  reqs[i] = { "/access_root_dir" }
                else
                  reqs[i] = { "/access_root_dir2" }
                end
            end
            local resps = { ngx.location.capture_multi(reqs) }
            for i, resp in ipairs(resps) do
                ngx.say(resp.status)
            end
        }
    }
_EOC_

    $block->set_value("config", $config);
    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();


__DATA__

=== TEST 1: limit-conn
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local data = {
                uri = "/*",
                plugins = {
                    workflow = {
                        rules = {
                            {
                                case = {
                                    {"uri", "==", "/limit_conn"}
                                },
                                actions = {
                                    {
                                        "limit-conn",
                                        {
                                          conn = 2,
                                          burst = 1,
                                          default_conn_delay = 0.1,
                                          rejected_code = 503,
                                          key = "remote_addr"
                                        }
                                    }
                                }
                            }
                        }
                    }
                },
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: exceeding the burst
--- request
GET /test_concurrency
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



=== TEST 3: two limit-conn configurations
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local data = {
                uri = "/*",
                plugins = {
                    workflow = {
                        rules = {
                            {
                                case = {
                                    {"uri", "==", "/limit_conn"}
                                },
                                actions = {
                                    {
                                        "limit-conn",
                                        {
                                          conn = 2,
                                          burst = 1,
                                          default_conn_delay = 0.1,
                                          rejected_code = 503,
                                          key = "remote_addr"
                                        }
                                    }
                                }
                            },
                            {
                                case = {
                                    {"uri", "==", "/limit_conn2"}
                                },
                                actions = {
                                    {
                                        "limit-conn",
                                        {
                                          conn = 2,
                                          burst = 1,
                                          default_conn_delay = 0.1,
                                          rejected_code = 503,
                                          key = "remote_addr"
                                        }
                                    }
                                }
                            }
                        }
                    }
                },
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: exceeding the burst
--- request
GET /test_concurrency2
--- timeout: 10s
--- response_body
404
200
404
200
404
200
503
503
503
503



=== TEST 5: set up workflow with limit-conn in global rule, and a route with cors
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                 ngx.HTTP_PUT,
                 json.encode({
                    plugins = {
                        workflow = {
                            rules = {
                                {
                                    case = {
                                        {"uri", "==", "/hello"}
                                    },
                                    actions = {
                                        {
                                            "limit-conn",
                                            {
                                                conn = 2,
                                                burst = 1,
                                                default_conn_delay = 0.1,
                                                rejected_code = 503,
                                                key = "remote_addr"
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                 })
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 json.encode({
                    uri = "/hello",
                    plugins = {
                        cors = {}
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:1980"] = 1
                        },
                        type = "roundrobin"
                    }
                 })
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 6: OPTIONS preflight finished by cors in rewrite phase, workflow log phase should not fail
--- request
OPTIONS /hello
--- more_headers
Origin: https://sub.domain.com
Access-Control-Request-Method: GET
--- error_code: 200
--- no_error_log
_workflow_cache



=== TEST 7: clean up
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1', ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed
