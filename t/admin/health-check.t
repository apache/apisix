use t::APISix 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
log_level("info");

run_tests;

__DATA__

=== TEST 1: active
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
                        "type": "roundrobin",
                        "checks": {
                            "active": {
                                "http_path": "/status",
                                "host": "foo.com",
                                "healthy": {
                                    "interval": 2,
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "interval": 1,
                                    "http_failures": 2
                                }
                            }
                        }
                    },
                    "uri": "/index.html"
                }]],
                [[{
                    "node": {
                        "value": {
                            "methods": ["GET"],
                            "uri": "/index.html",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin",
                                "checks": {
                                    "active": {
                                        "http_path": "/status",
                                        "host": "foo.com",
                                        "healthy": {
                                            "interval": 2,
                                            "successes": 1
                                        },
                                        "unhealthy": {
                                            "interval": 1,
                                            "http_failures": 2
                                        }
                                    }
                                }
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



=== TEST 2: passive
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
                        "type": "roundrobin",
                        "checks": {
                            "passive": {
                                "healthy": {
                                    "http_statuses": [200, 201],
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "http_statuses": [500],
                                    "http_failures": 2
                                }
                            }
                        }
                    },
                    "uri": "/index.html"
                }]],
                [[{
                    "node": {
                        "value": {
                            "methods": ["GET"],
                            "uri": "/index.html",
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:8080": 1
                                },
                                "type": "roundrobin",
                                "checks": {
                                    "passive": {
                                        "healthy": {
                                            "http_statuses": [200, 201],
                                            "successes": 1
                                        },
                                        "unhealthy": {
                                            "http_statuses": [500],
                                            "http_failures": 2
                                        }
                                    }
                                }
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
