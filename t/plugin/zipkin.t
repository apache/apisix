use t::APISix 'no_plan';

repeat_each(2);
no_long_string();
no_root_location();
log_level("info");
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.zipkin")
            local ok, err = plugin.check_schema({endpoint = 'http://127.0.0.1', sample_ratio = 0.001})
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



=== TEST 2: default value of sample_ratio
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.zipkin")
            local ok, err = plugin.check_schema({endpoint = 'http://127.0.0.1'})
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
--- SKIP



=== TEST 3: wrong value of ratio
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.zipkin")
            local ok, err = plugin.check_schema({endpoint = 'http://127.0.0.1', sample_ratio = -0.1})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
invalid "minimum" in docuement at pointer "#/sample_ratio"
done
--- no_error_log
[error]



=== TEST 4: wrong value of ratio
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.zipkin")
            local ok, err = plugin.check_schema({endpoint = 'http://127.0.0.1', sample_ratio = 2})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
invalid "maximum" in docuement at pointer "#/sample_ratio"
done
--- no_error_log
[error]



=== TEST 5: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "zipkin": {
                                "endpoint": "http://127.0.0.1:1982/mock_zipkin",
                                "sample_ratio": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "zipkin": {
                                    "endpoint": "http://127.0.0.1:1982/mock_zipkin",
                                    "sample_ratio": 1
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/opentracing"
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



=== TEST 6: tiger zipkin
--- request
GET /opentracing
--- response_body
opentracing
--- grep_error_log eval
qr/\[info\].*/
--- grep_error_log_out eval
qr{report2endpoint ok}



=== TEST 7: change sample ratio
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "zipkin": {
                                "endpoint": "http://127.0.0.1:1982/mock_zipkin",
                                "sample_ratio": 0.00001
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "zipkin": {
                                    "endpoint": "http://127.0.0.1:1982/mock_zipkin",
                                    "sample_ratio": 0.00001
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/opentracing"
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



=== TEST 8: not tiger zipkin
--- request
GET /opentracing
--- response_body
opentracing
--- no_error_log
report2endpoint ok



=== TEST 9: disabled
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
                        "uri": "/opentracing"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/opentracing"
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



=== TEST 10: not tiger zipkin
--- request
GET /opentracing
--- response_body
opentracing
--- no_error_log
report2endpoint ok
