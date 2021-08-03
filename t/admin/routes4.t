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
no_root_location();
no_shuffle();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: set route with ttl
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local core = require("apisix.core")
        -- set
        local code, body, res = t('/apisix/admin/routes/1?ttl=1',
            ngx.HTTP_PUT,
            [[{
                "upstream": {
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin"
                },
                "uri": "/index.html"
            }]]
            )

        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end

        -- get
        code, body = t('/apisix/admin/routes/1?ttl=1',
            ngx.HTTP_GET,
            nil,
            [[{
                "node": {
                    "value": {
                        "uri": "/index.html"
                    },
                    "key": "/apisix/routes/1"
                }
            }]]
        )

        ngx.say("code: ", code)
        ngx.say(body)

        -- etcd v3 would still get the value at 2s, don't know why yet
        ngx.sleep(2.5)

        -- get again
        code, body, res = t('/apisix/admin/routes/1', ngx.HTTP_GET)

        ngx.say("code: ", code)
        ngx.say("message: ", core.json.decode(body).message)
    }
}
--- response_body
code: 200
passed
code: 404
message: Key not found
--- timeout: 5



=== TEST 2: post route with ttl
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local core = require("apisix.core")

        local code, body, res = t('/apisix/admin/routes?ttl=1',
            ngx.HTTP_POST,
            [[{
                "methods": ["GET"],
                "upstream": {
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin"
                },
                "uri": "/index.html"
            }]],
            [[{"action": "create"}]]
            )

        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end

        ngx.say("[push] succ: ", body)
        ngx.sleep(2.5)

        local id = string.sub(res.node.key, #"/apisix/routes/" + 1)
        code, body = t('/apisix/admin/routes/' .. id, ngx.HTTP_GET)

        ngx.say("code: ", code)
        ngx.say("message: ", core.json.decode(body).message)
    }
}
--- response_body
[push] succ: passed
code: 404
message: Key not found
--- timeout: 5



=== TEST 3: invalid argument: ttl
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body, res = t('/apisix/admin/routes?ttl=xxx',
            ngx.HTTP_PUT,
            [[{
                "upstream": {
                    "nodes": {
                        "127.0.0.1:8080": 1
                    },
                    "type": "roundrobin"
                },
                "uri": "/index.html"
            }]]
            )

        if code >= 300 then
            ngx.status = code
            ngx.print(body)
            return
        end

        ngx.say("[push] succ: ", body)
    }
}
--- error_code: 400
--- response_body
{"error_msg":"invalid argument ttl: should be a number"}



=== TEST 4: set route(id: 1, check priority)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route",
                    "uri": "/index.html"
                }]],
                [[{
                    "node": {
                        "value": {
                            "priority": 0
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 5: set route(id: 1 + priority: 0)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route",
                    "uri": "/index.html",
                    "priority": 1
                }]],
                [[{
                    "node": {
                        "value": {
                            "priority": 1
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 6: set route(id: 1) and upstream(type:chash, default hash_on: vars, missing key)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "chash"
                    },
                    "desc": "new route",
                    "uri": "/index.html"
                }]])
            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"missing key"}



=== TEST 7: set route(id: 1) and upstream(type:chash, hash_on: header, missing key)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "chash",
                        "hash_on":"header"
                    },
                    "desc": "new route",
                    "uri": "/index.html"
                }]])
            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"missing key"}



=== TEST 8: set route(id: 1) and upstream(type:chash, hash_on: cookie, missing key)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "chash",
                        "hash_on":"cookie"
                    },
                    "desc": "new route",
                    "uri": "/index.html"
                }]])
            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"missing key"}



=== TEST 9: set route(id: 1) and upstream(type:chash, hash_on: consumer, missing key is ok)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "chash",
                        "hash_on":"consumer"
                    },
                    "desc": "new route",
                    "uri": "/index.html"
                }]])

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 10: set route(id: 1 + name: test name)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "name": "test name",
                    "uri": "/index.html"
                }]],
                [[{
                    "node": {
                        "value": {
                            "name": "test name"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: string id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/a-b-c-ABC_0123',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/index.html"
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



=== TEST 12: string id(delete)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/a-b-c-ABC_0123',
                ngx.HTTP_DELETE
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 13: invalid string id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/*invalid',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/index.html"
                }]]
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- error_code: 400



=== TEST 14: Verify Response Content-Type=application/json
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            httpc:set_timeout(500)
            httpc:connect(ngx.var.server_addr, ngx.var.server_port)
            local res, err = httpc:request(
                {
                    path = '/apisix/admin/routes/1?ttl=1',
                    method = "GET",
                }
            )

            ngx.header["Content-Type"] = res.headers["Content-Type"]
            ngx.status = 200
            ngx.say("passed")
        }
    }
--- response_headers
Content-Type: application/json



=== TEST 15: set route with size 36k (temporary file to store request body)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local core = require("apisix.core")
            local s = string.rep("a", 1024 * 35)
            local req_body = [[{
                "upstream": {
                    "nodes": {
                        "]] .. s .. [[": 1
                    },
                    "type": "roundrobin"
                },
                "uri": "/index.html"
            }]]

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT, req_body)

            if code >= 300 then
                ngx.status = code
            end

            ngx.say("req size: ", #req_body)
            ngx.say(body)
        }
    }
--- response_body
req size: 36066
passed
--- error_log
a client request body is buffered to a temporary file



=== TEST 16: route size more than 1.5 MiB
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local s = string.rep( "a", 1024 * 1024 * 1.6 )
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "]] .. s .. [[",
                    "uri": "/index.html"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"invalid request body: request size 1678025 is greater than the maximum size 1572864 allowed"}
--- error_log
failed to read request body: request size 1678025 is greater than the maximum size 1572864 allowed



=== TEST 17: uri + plugins + script  failed
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-count": {
                                "count": 2,
                                "time_window": 60,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            }
                        },
                        "script": "local _M = {} \n function _M.access(api_ctx) \n ngx.log(ngx.INFO,\"hit access phase\") \n end \nreturn _M",
                        "uri": "/index.html"
                }]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.say(message)
                return
            end
        }
    }
--- error_code: 400
--- response_body_like
{"error_msg":"invalid configuration: value wasn't supposed to match schema"}



=== TEST 18: invalid route: multi nodes with `node` mode to pass host
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET", "GET"],
                        "upstream": {
                            "nodes": {
                                "httpbin.org:8080": 1,
                                "test.com:8080": 1
                            },
                            "type": "roundrobin",
                            "pass_host": "node"
                        },
                        "uri": "/index.html"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400



=== TEST 19: set route(with labels)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "labels": {
                        "build": "16",
                        "env": "production",
                        "version": "v2"
                    },

                    "uri": "/index.html"
                }]],
                [[{
                    "node": {
                        "value": {
                            "methods": [
                                "GET"
                            ],
                            "uri": "/index.html",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            },
                            "labels": {
                                "build": "16",
                                "env": "production",
                                "version": "v2"
                            }
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 20: patch route(change labels)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                [[{
                    "labels": {
                        "build": "17"
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "methods": [
                                "GET"
                            ],
                            "uri": "/index.html",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            },
                            "labels": {
                                "env": "production",
                                "version": "v2",
                                "build": "17"
                            }
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "compareAndSwap"
                }]]
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 21: invalid format of label value: set route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "uri": "/index.html",
                        "labels": {
	                        "env": ["production", "release"]
                        }
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"labels\" validation failed: failed to validate env (matching \".*\"): wrong type: expected string, got table"}



=== TEST 22: create route with create_time and update_time(id : 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/index.html",
                    "create_time": 1602883670,
                    "update_time": 1602893670
                }]],
                [[{
                    "node": {
                        "value": {
                            "uri": "/index.html",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            },
                            "create_time": 1602883670,
                            "update_time": 1602893670
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 23: delete test route(id : 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message = t('/apisix/admin/routes/1',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
                )
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- response_body
[delete] code: 200 message: passed
