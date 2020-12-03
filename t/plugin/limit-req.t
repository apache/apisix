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

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.limit-req")
            local ok, err = plugin.check_schema({rate = 1, burst = 0, rejected_code = 503, key = 'remote_addr'})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 2: wrong value of key
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.limit-conn")
            local ok, err = plugin.check_schema({burst = 0, rejected_code = 503, key = 'remote_addr'})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body_like eval
qr/property "(conn|default_conn_delay)" is required
done
/
--- no_error_log
[error]



=== TEST 3: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 4,
                            "burst": 2,
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
                        "desc": "upstream_node",
                        "uri": "/hello"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "limit-req": {
                                    "rate": 4,
                                    "burst": 2,
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
                            "desc": "upstream_node",
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 4: not exceeding the burst
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200, 200]
--- no_error_log
[error]



=== TEST 5: update plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 0.1,
                            "burst": 0.1,
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
                        "uri": "/hello"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "limit-req": {
                                    "rate": 0.1,
                                    "burst": 0.1,
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
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 6: exceeding the burst
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 503, 503, 503]
--- no_error_log
[error]



=== TEST 7: wrong type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-req": {
                            "rate": -1,
                            "burst": 0.1,
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
                        "uri": "/hello"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "limit-req": {
                                    "rate": -1,
                                    "burst": 0.1,
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
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
{"error_msg":"failed to check the configuration of plugin limit-req err: property \"rate\" validation failed: expected -1 to be greater than 0"}
--- no_error_log
[error]



=== TEST 8: disable plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
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
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 9: exceeding the burst
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200, 200]
--- no_error_log
[error]



=== TEST 10: set route (key: server_addr)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 4,
                            "burst": 2,
                            "rejected_code": 503,
                            "key": "server_addr"
                        }
                    },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "upstream_node",
                        "uri": "/hello"
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
--- no_error_log
[error]



=== TEST 11: default rejected_code
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 4,
                            "burst": 2,
                            "key": "remote_addr"
                        }
                    },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "upstream_node",
                        "uri": "/hello"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "limit-req": {
                                    "rejected_code": 503,
                                    "key": "remote_addr"
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
--- no_error_log
[error]



=== TEST 12: consumer binds the limit-req plugin and `key` is `consumer_name`
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "new_consumer",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-jack"
                        },
                        "limit-req": {
                            "rate": 3,
                            "burst": 2,
                            "rejected_code": 403,
                            "key": "consumer_name"
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "new_consumer",
                            "plugins": {
                               "key-auth": {
                                    "key": "auth-jack"
                                },
                                "limit-req": {
                                    "rate": 3,
                                    "burst": 2,
                                    "rejected_code": 403,
                                    "key": "consumer_name"
                                }
                            }
                        }
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 13: route add "key-auth" plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "key-auth": {} 
                    },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "upstream_node",
                        "uri": "/hello"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "key-auth": {}
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "desc": "upstream_node",
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 14: not exceeding the burst
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- more_headers
apikey: auth-jack
--- error_code eval
[200, 200, 200]
--- no_error_log
[error]



=== TEST 15: update the limit-req plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "new_consumer",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-jack"
                        },
                        "limit-req": {
                            "rate": 0.1,
                            "burst": 0.1,
                            "rejected_code": 403,
                            "key": "consumer_name"
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "new_consumer",
                            "plugins": {
                               "key-auth": {
                                    "key": "auth-jack"
                                },
                                "limit-req": {
                                    "rate": 0.1,
                                    "burst": 0.1,
                                    "rejected_code": 403,
                                    "key": "consumer_name"
                                }
                            }
                        }
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 16: exceeding the burst
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- more_headers
apikey: auth-jack
--- error_code eval
[403, 403, 403, 403]
--- no_error_log
[error]



=== TEST 17: key is consumer_name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "limit-req": {
                            "rate": 2,
                            "burst": 1,
                            "key": "consumer_name"
                        }
                    },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "desc": "upstream_node",
                        "uri": "/hello"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "limit-req": {
                                    "rate": 2,
                                    "burst": 1,
                                    "key": "consumer_name"
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "desc": "upstream_node",
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
--- no_error_log
[error]



=== TEST 18: get "consumer_name" is empty
--- request
GET /hello
--- error_code: 500
--- response_body
{"message":"Consumer not found."}
--- error_log
[error]



=== TEST 19: delete consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/new_consumer', ngx.HTTP_DELETE)

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 20： delete route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)

            ngx.status =code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]
