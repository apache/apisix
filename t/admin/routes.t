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

run_tests;

__DATA__

=== TEST 1: set route(id: 1)
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
                            "methods": [
                                "GET"
                            ],
                            "uri": "/index.html",
                            "desc": "new route",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: get route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_GET,
                 nil,
                [[{
                    "node": {
                        "value": {
                            "methods": [
                                "GET"
                            ],
                            "uri": "/index.html",
                            "desc": "new route",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            }
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "get"
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



=== TEST 3: delete route(id: 1)
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
--- request
GET /t
--- response_body
[delete] code: 200 message: passed
--- no_error_log
[error]



=== TEST 4: delete route(id: not_found)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/not_found',
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
                )
            ngx.say("[delete] code: ", code)
        }
    }
--- request
GET /t
--- response_body
[delete] code: 404
--- no_error_log
[error]



=== TEST 5: post route + delete
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/routes',
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
                            }
                        }
                    },
                    "action": "create"
                }]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say("[push] code: ", code, " message: ", message)

            local id = string.sub(res.node.key, #"/apisix/routes/" + 1)
            code, message = t('/apisix/admin/routes/' .. id,
                 ngx.HTTP_DELETE,
                 nil,
                 [[{
                    "action": "delete"
                }]]
                )
            ngx.say("[delete] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[push] code: 200 message: passed
[delete] code: 200 message: passed
--- no_error_log
[error]



=== TEST 6: uri + upstream
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/index.html"
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
                            }
                        }
                    },
                    "action": "set"
                }]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say("[push] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[push] code: 200 message: passed
--- no_error_log
[error]



=== TEST 7: uri + plugins
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
                        "uri": "/index.html"
                }]],
                [[{
                    "node": {
                        "value": {
                            "uri": "/index.html",
                            "plugins": {
                                "limit-count": {
                                    "count": 2,
                                    "time_window": 60,
                                    "rejected_code": 503,
                                    "key": "remote_addr"
                                }
                            }
                        }
                    },
                    "action": "set"
                }]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say("[push] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[push] code: 200 message: passed
--- no_error_log
[error]



=== TEST 8: invalid empty plugins (todo)
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, message, res = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/index.html"
                }]]
                )

            if code ~= 200 then
                ngx.status = code
                ngx.print(message)
                return
            end

            ngx.say("[push] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- error_code: 400
--- SKIP



=== TEST 9: invalid route: duplicate method
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
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/index.html"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body_like
--- no_error_log
[error]



=== TEST 10: invalid method
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["invalid_method"],
                        "uri": "/index.html"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"methods\" validation failed: failed to validate item 1: matches non of the enum values"}
--- no_error_log
[error]



=== TEST 11: invalid service id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "service_id": "invalid_id$",
                        "uri": "/index.html"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"service_id\" validation failed: object matches none of the requireds"}
--- no_error_log
[error]



=== TEST 12: service id: not exist
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "service_id": "99999999999999",
                        "uri": "/index.html"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to fetch service info by service id [99999999999999], response code: 404"}
--- no_error_log
[error]



=== TEST 13: invalid id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                     "id": 3,
                    "uri": "/index.html"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"wrong route id"}
--- no_error_log
[error]



=== TEST 14: id in the rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes',
                ngx.HTTP_PUT,
                [[{
                    "id": "1",
                    "plugins":{},
                    "uri": "/index.html"
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



=== TEST 15: integer id less than 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes',
                 ngx.HTTP_PUT,
                 [[{
                    "id": -100,
                    "uri": "/index.html"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"id\" validation failed: object matches none of the requireds"}
--- no_error_log
[error]



=== TEST 16: invalid upstream_id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream_id": "invalid$",
                    "uri": "/index.html"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"upstream_id\" validation failed: object matches none of the requireds"}
--- no_error_log
[error]



=== TEST 17: not exist upstream_id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream_id": "99999999",
                    "uri": "/index.html"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to fetch upstream info by upstream id [99999999], response code: 404"}
--- no_error_log
[error]



=== TEST 18: wrong route id, do not need it
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes',
                 ngx.HTTP_POST,
                 [[{
                    "id": 1,
                    "plugins":{},
                    "uri": "/index.html"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"wrong route id, do not need it"}
--- no_error_log
[error]



=== TEST 19: wrong route id, do not need it
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_POST,
                 [[{
                    "plugins":{},
                    "uri": "/index.html"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"wrong route id, do not need it"}
--- no_error_log
[error]



=== TEST 20: limit-count with `disable` option
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
                            "disable": true
                        }
                    },
                    "uri": "/index.html"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say("[push] code: ", code, " message: ", message)
        }
    }
--- request
GET /t
--- response_body
[push] code: 200 message: passed
--- no_error_log
[error]



=== TEST 21: host: *.foo.com
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "host": "*.foo.com",
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/index.html"
                }]],
                [[{
                    "node": {
                        "value": {
                            "host": "*.foo.com",
                            "uri": "/index.html",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 22: invalid host: a.*.foo.com
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "host": "a.*.foo.com",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/index.html"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"host\" validation failed: failed to match pattern \"^\\\\*?[0-9a-zA-Z-.]+$\" with \"a.*.foo.com\""}
--- no_error_log
[error]



=== TEST 23: invalid host: *.a.*.foo.com
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "host": "*.a.*.foo.com",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/index.html"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"host\" validation failed: failed to match pattern \"^\\\\*?[0-9a-zA-Z-.]+$\" with \"*.a.*.foo.com\""}
--- no_error_log
[error]



=== TEST 24: remote_addr: 127.0.0.1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "remote_addr": "127.0.0.1",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/index.html"
                }]],
                [[{
                    "node": {
                        "value": {
                            "remote_addr": "127.0.0.1",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/index.html"
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



=== TEST 25: remote_addr: 127.0.0.1/24
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "remote_addr": "127.0.0.0/24",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/index.html"
                }]],
                [[{
                    "node": {
                        "value": {
                            "remote_addr": "127.0.0.0/24",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/index.html"
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



=== TEST 26: remote_addr: 127.0.0.33333
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "remote_addr": "127.0.0.33333",
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
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"remote_addr\" validation failed: object matches none of the requireds"}
--- no_error_log
[error]



=== TEST 27: all method
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET", "POST", "PUT", "DELETE", "PATCH",
                                    "HEAD", "OPTIONS", "CONNECT", "TRACE"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:8080": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/index.html"
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



=== TEST 28: patch route(new methods)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                [[{
                    "methods": ["GET", null, null, null, null, null, null, null, null]
                }]],
                [[{
                    "node": {
                        "value": {
                            "methods": [
                                "GET"
                            ]
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 29: patch route(new uri)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                [[{
                    "uri": "/patch_test"
                }]],
                [[{
                    "node": {
                        "value": {
                            "uri": "/patch_test"
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 30: patch route(multi)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": null,
                            "127.0.0.2:8080": 1
                        }
                    },
                    "desc": "new route"
                }]],
                [[{
                    "node": {
                        "value": {
                            "methods": [
                                "GET"
                            ],
                            "uri": "/patch_test",
                            "desc": "new route",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.2:8080": 1
                                },
                                "type": "roundrobin"
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 31: multiple hosts
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/index.html",
                    "hosts": ["foo.com", "*.bar.com"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route"
                }]],
                [[{
                    "node": {
                        "value": {
                            "hosts": ["foo.com", "*.bar.com"]
                        }
                    }
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



=== TEST 32: enable hosts and host together
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/index.html",
                    "host": "xxx.com",
                    "hosts": ["foo.com", "*.bar.com"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route"
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"only one of host or hosts is allowed"}
--- no_error_log
[error]



=== TEST 33: multiple remote_addrs
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/index.html",
                    "remote_addrs": ["127.0.0.1", "192.0.0.1/8", "::1", "fe80::/32"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route"
                }]],
                [[{
                    "node": {
                        "value": {
                            "remote_addrs": ["127.0.0.1", "192.0.0.1/8", "::1", "fe80::/32"]
                        }
                    }
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



=== TEST 34: multiple vars
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uri": "/index.html",
                    "vars": [["arg_name", "==", "json"], ["arg_age", ">", 18]],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route"
                }]=],
                [=[{
                    "node": {
                        "value": {
                            "vars": [["arg_name", "==", "json"], ["arg_age", ">", 18]]
                        }
                    }
                }]=]
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



=== TEST 35: filter function
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uri": "/index.html",
                    "filter_func": "function(vars) return vars.arg_name == 'json' end",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    }
                }]=],
                [=[{
                    "node": {
                        "value": {
                            "filter_func": "function(vars) return vars.arg_name == 'json' end"
                        }
                    }
                }]=]
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



=== TEST 36: filter function (invalid)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uri": "/index.html",
                    "filter_func": "function(vars) ",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    }
                }]=]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to load 'filter_func' string: [string \"return function(vars) \"]:1: 'end' expected near '<eof>'"}
--- no_error_log
[error]



=== TEST 37: Support for multiple URIs
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "uris": ["/index.html","/index2.html"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin"
                    }
                }]=]
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



=== TEST 38: set route with ttl
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

        ngx.say("code: ", code)
        ngx.say(body)

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

        ngx.sleep(2)

        -- get again
        code, body, res = t('/apisix/admin/routes/1', ngx.HTTP_GET)

        ngx.say("code: ", code)
        ngx.say("message: ", core.json.decode(body).message)
    }
}
--- request
GET /t
--- response_body
code: 200
passed
code: 200
passed
code: 404
message: Key not found
--- no_error_log
[error]
--- timeout: 5



=== TEST 39: post route with ttl
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
        ngx.sleep(2)

        local id = string.sub(res.node.key, #"/apisix/routes/" + 1)
        code, body = t('/apisix/admin/routes/' .. id, ngx.HTTP_GET)

        ngx.say("code: ", code)
        ngx.say("message: ", core.json.decode(body).message)
    }
}
--- request
GET /t
--- response_body
[push] succ: passed
code: 404
message: Key not found
--- no_error_log
[error]
--- timeout: 5



=== TEST 40: invalid argument: ttl
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
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid argument ttl: should be a number"}
--- no_error_log
[error]



=== TEST 41: set route(id: 1, check priority)
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 42: set route(id: 1 + priority: 0)
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 43: set route(id: 1) and upstream(type:chash, default hash_on: vars, missing key)
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
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"missing key"}
--- no_error_log
[error]



=== TEST 44: set route(id: 1) and upstream(type:chash, hash_on: header, missing key)
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
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"missing key"}
--- no_error_log
[error]



=== TEST 45: set route(id: 1) and upstream(type:chash, hash_on: cookie, missing key)
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
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"missing key"}
--- no_error_log
[error]



=== TEST 46: set route(id: 1) and upstream(type:chash, hash_on: consumer, missing key is ok)
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 47: set route(id: 1 + name: test name)
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]

=== TEST 48: string id
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 49: string id(delete)
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 50: invalid string id
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
--- request
GET /t
--- error_code: 400
--- no_error_log
[error]


=== TEST 50: Verify Response Content-Type=applciation/json
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
--- request
GET /t   
--- response_headers
Content-Type: application/json
