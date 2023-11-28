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

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();


__DATA__

=== TEST 1: multiple cases with different actions(return & limit-count)
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
                                    {"uri", "==", "/hello"}
                                },
                                actions = {
                                    {
                                        "return",
                                        {
                                            code = 403
                                        }
                                    }
                                }
                            },
                            {
                                case = {
                                    {"uri", "==", "/hello1"}
                                },
                                actions = {
                                    {
                                        "limit-count",
                                        {
                                            count = 1,
                                            time_window = 60,
                                            rejected_code = 503
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



=== TEST 2: cross-hit case 1 and case 2, trigger actions by isolation
--- pipelined_requests eval
["GET /hello", "GET /hello1", "GET /hello1"]
--- error_code eval
[403, 200, 503]



=== TEST 3: the conf in actions is isolation
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
                                    {"uri", "==", "/hello"}
                                },
                                actions = {
                                    {
                                        "limit-count",
                                        {
                                            count = 3,
                                            time_window = 60,
                                            rejected_code = 503,
                                            key = "remote_addr"
                                        }
                                    }
                                }
                            },
                            {
                                case = {
                                    {"uri", "==", "/hello1"}
                                },
                                actions = {
                                    {
                                        "limit-count",
                                        {
                                            count = 3,
                                            time_window = 60,
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



=== TEST 4: cross-hit case 1 and case 2, trigger actions by isolation
--- pipelined_requests eval
["GET /hello", "GET /hello1", "GET /hello", "GET /hello1"]
--- error_code eval
[200, 200, 200, 200]



=== TEST 5: cross-hit case 1 and case 2, up limit by isolation 2
--- pipelined_requests eval
["GET /hello", "GET /hello1", "GET /hello", "GET /hello1"]
--- error_code eval
[200, 200, 503, 503]



=== TEST 6: different actions with different limit count conf, up limit by isolation
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
                                    {"uri", "==", "/hello"}
                                },
                                actions = {
                                    {
                                        "limit-count",
                                        {
                                            count = 1,
                                            time_window = 60,
                                            rejected_code = 503,
                                            key = "remote_addr"
                                        }
                                    }
                                }
                            },
                            {
                                case = {
                                    {"uri", "==", "/hello1"}
                                },
                                actions = {
                                    {
                                        "limit-count",
                                        {
                                            count = 2,
                                            time_window = 60,
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



=== TEST 7: case 1 up limit, case 2 psssed
--- pipelined_requests eval
["GET /hello", "GET /hello1", "GET /hello", "GET /hello1"]
--- error_code eval
[200, 200, 503, 200]



=== TEST 8: test no rules
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local data = {
                uri = "/*",
                plugins = {
                    workflow = {
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

            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin workflow err: property \"rules\" is required"}
