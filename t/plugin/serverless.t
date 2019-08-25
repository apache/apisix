use t::APISix 'no_plan';

repeat_each(2);
no_long_string();
no_root_location();
run_tests;

__DATA__

=== TEST 1: use default phase
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
done
--- no_error_log
[error]



=== TEST 2: phase is rewrite
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.serverless-pre-function")
            local ok, err = plugin.check_schema({phase = 'rewrite', functions = {"local a = 123;"}})
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
            local ok, err = plugin.check_schema({phase = 'log', functions = {"local a = 123;"}})
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
            local ok, err = plugin.check_schema({phase = 'abc', functions = {"local a = 123;"}})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
invalid "enum" in docuement at pointer "#/phase"
done
--- no_error_log
[error]



=== TEST 5: set route and serverless-post-function plugin
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



=== TEST 6: check plugin
--- request
GET /hello
--- error_code: 201
--- error_log
serverless post function



=== TEST 7: set route and serverless-pre-function plugin
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



=== TEST 8: check plugin
--- request
GET /hello
--- error_code: 201
--- error_log
serverless pre function



=== TEST 9: serverless-pre-function and serverless-post-function
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



=== TEST 10: check plugin
--- request
GET /hello
--- error_code: 201
--- error_log
serverless pre function
serverless post function



=== TEST 11: log phase and serverless-pre-function plugin
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



=== TEST 12: check plugin
--- request
GET /hello
--- error_log
serverless pre function
