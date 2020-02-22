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
run_tests;

__DATA__

=== TEST 1: use default phase
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.serverless-pre-function")
            local ok, err = plugin.check_schema({functions = {"return function() ngx.log(ngx.ERR, 'serverless post function'); ngx.exit(201); end"}})
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



=== TEST 2: phase is rewrite
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.serverless-pre-function")
            local ok, err = plugin.check_schema({phase = 'rewrite', functions = {"return function() ngx.log(ngx.ERR, 'serverless post function'); ngx.exit(201); end"}})
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



=== TEST 3: phase is log for post function
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.serverless-post-function")
            local ok, err = plugin.check_schema({phase = 'log', functions = {"return function() ngx.log(ngx.ERR, 'serverless post function'); ngx.exit(201); end"}})
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



=== TEST 4: invalid phase
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.serverless-pre-function")
            local ok, err = plugin.check_schema({phase = 'abc', functions = {"return function() ngx.log(ngx.ERR, 'serverless post function'); ngx.exit(201); end"}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "phase" validation failed: matches non of the enum values
done
--- no_error_log
[error]



=== TEST 5: only accept function
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.serverless-pre-function")
            local ok, err = plugin.check_schema({functions = {"local a = 123;"}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
only accept Lua function, the input code type is nil
done
--- no_error_log
[error]



=== TEST 6: invalid lua code
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.serverless-pre-function")
            local ok, err = plugin.check_schema({functions = {"a"}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
failed to loadstring: [string "a"]:1: '=' expected near '<eof>'
done
--- no_error_log
[error]



=== TEST 7: set route and serverless-post-function plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-post-function": {
                            "functions" : ["return function() ngx.log(ngx.ERR, 'serverless post function'); ngx.exit(201); end"]
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
                                "serverless-post-function": {
                                    "functions" : ["return function() ngx.log(ngx.ERR, 'serverless post function'); ngx.exit(201); end"]
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



=== TEST 8: check plugin
--- request
GET /hello
--- error_code: 201
--- error_log
serverless post function



=== TEST 9: set route and serverless-pre-function plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "functions" : ["return function() ngx.log(ngx.ERR, 'serverless pre function'); ngx.exit(201); end"]
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
                                "serverless-pre-function": {
                                    "functions" : ["return function() ngx.log(ngx.ERR, 'serverless pre function'); ngx.exit(201); end"]
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



=== TEST 10: check plugin
--- request
GET /hello
--- error_code: 201
--- error_log
serverless pre function



=== TEST 11: serverless-pre-function and serverless-post-function
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "functions" : ["return function() ngx.log(ngx.ERR, 'serverless pre function'); end"]
                        },
                        "serverless-post-function": {
                            "functions" : ["return function() ngx.log(ngx.ERR, 'serverless post function'); ngx.exit(201); end"]
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
                                "serverless-pre-function": {
                                    "functions" : ["return function() ngx.log(ngx.ERR, 'serverless pre function'); end"]
                                },
                                "serverless-post-function": {
                                    "functions" : ["return function() ngx.log(ngx.ERR, 'serverless post function'); ngx.exit(201); end"]
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



=== TEST 12: check plugin
--- request
GET /hello
--- error_code: 201
--- error_log
serverless pre function
serverless post function



=== TEST 13: log phase and serverless-pre-function plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "log",
                            "functions" : ["return function() ngx.log(ngx.ERR, 'serverless pre function'); end"]
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
                                "serverless-pre-function": {
                                    "phase": "log",
                                    "functions" : ["return function() ngx.log(ngx.ERR, 'serverless pre function'); end"]
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



=== TEST 14: check plugin
--- request
GET /hello
--- error_log
serverless pre function



=== TEST 15: functions
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions" : ["return function() ngx.log(ngx.ERR, 'one'); end", "return function() ngx.log(ngx.ERR, 'two'); end"]
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
                                "serverless-pre-function": {
                                    "phase": "rewrite",
                                    "functions" : ["return function() ngx.log(ngx.ERR, 'one'); end", "return function() ngx.log(ngx.ERR, 'two'); end"]
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



=== TEST 16: check plugin
--- request
GET /hello
--- error_log
one
two



=== TEST 17: closure
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "log",
                            "functions" : ["local count = 1; return function() count = count + 1;ngx.log(ngx.ERR, 'serverless pre function:', count); end"]
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
                                "serverless-pre-function": {
                                    "phase": "log",
                            "functions" : ["local count = 1; return function() count = count + 1;ngx.log(ngx.ERR, 'serverless pre function:', count); end"]
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



=== TEST 18: check plugin
--- request
GET /hello
--- error_log
serverless pre function:2
