use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
log_level("info");

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: invalid pre_function
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count": {
                                "count": 2,
                                "time_window": 60,
                                "rejected_code": 503,
                                "key": "remote_addr",
                                "_meta": {
                                    "pre_function": "not a function"
                                }
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
--- error_code: 400
--- response_body
{"error_msg":"failed to load _meta.pre_function in plugin limit-count: [string \"meta pre_function\"]:1: unexpected symbol near 'not'"}



=== TEST 2: attempt setting pre_function in _meta with a typo in `pre_function`
# this is to test the case where user (or CP) would attempt configuring pre_function
# using incorrect field name, this validation is achieved by setting `additionalProperties = false`
# in schema_def.lua
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count": {
                                "count": 2,
                                "time_window": 60,
                                "rejected_code": 503,
                                "key": "remote_addr",
                                "_meta": {
                                    "prefunction": "not a function"
                                }
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
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin limit-count err: property \"_meta\" validation failed: additional properties forbidden, found prefunction"}



=== TEST 3: pre_function with error in code
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count": {
                                "count": 2,
                                "time_window": 60,
                                "rejected_code": 503,
                                "key": "remote_addr",
                                "_meta": {
                                    "pre_function": "return function() print(invalid.index) end"
                                }
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
            ngx.say(body)
        }
    }
--- error_code: 200
--- response_body
passed



=== TEST 4: sending request will execute erroneous code and print error log
--- request
GET /hello
--- error_log
pre_function execution for plugin limit-count failed: [string "meta pre_function"]:1: attempt to index global 'invalid' (a nil value),



=== TEST 5: test pre_function sanity: correct function
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count": {
                                "count": 2,
                                "time_window": 60,
                                "rejected_code": 503,
                                "key": "remote_addr",
                                "_meta": {
                                    "pre_function": "return function(conf, ctx) ngx.log(ngx.WARN, 'hello ', ngx.req.get_headers()[\"User-Agent\"]) end"
                                }
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
            ngx.say(body)
        }
    }
--- error_code: 200
--- response_body
passed



=== TEST 6: request
--- request
GET /hello
--- more_headers
User-Agent: test-nginx
--- error_log
hello test-nginx



=== TEST 7: pre_function is executed in all phases
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "example-plugin": {
                            "i": 11,
                            "_meta": {
                                "pre_function": "return function(conf, ctx) ngx.log(ngx.WARN, 'hello: ', ngx.get_phase()) end"
                            }
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
            ngx.say(body)
        }
    }
--- error_code: 200
--- response_body
passed



=== TEST 8: request
--- request
GET /hello
--- error_log
hello: access
hello: header_filter
hello: body_filter
hello: log



=== TEST 9: test pre-function with proxy-rewrite, (rewrite phase)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/uri",
                            "headers": {
                                "x-api": "$example_var_name"
                            },
                            "_meta": {
                                "pre_function": "return function(conf, ctx) local core = require \"apisix.core\" core.ctx.register_var(\"example_var_name\", function(ctx) return \"example_var_value\" end) end"
                            }
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
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 10: hit route(header supports nginx variables)
--- request
GET /hello
--- response_body
uri: /uri
host: localhost
x-api: example_var_value
x-real-ip: 127.0.0.1
