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



=== TEST 3: invalid route: active.healthy.successes counter exceed maximum value
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "uri": "/index.html",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin",
                        "checks": {
                            "active": {
                                "healthy": {
                                    "successes": 255
                                }
                            },
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
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: invalid \"maximum\" in docuement at pointer \"#\/upstream\/checks\/active\/healthy\/successes\""}
--- no_error_log
[error]



=== TEST 4: invalid route: active.healthy.successes counter below the minimum value
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "uri": "/index.html",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin",
                        "checks": {
                            "active": {
                                "healthy": {
                                    "successes": 0
                                }
                            },
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
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: invalid \"minimum\" in docuement at pointer \"#\/upstream\/checks\/active\/healthy\/successes\""}
--- no_error_log
[error]



=== TEST 5: invalid route: wrong passive.unhealthy.http_statuses
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "uri": "/index.html",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin",
                        "checks": {
                            "active": {
                                "healthy": {
                                    "successes": 2
                                },
                                "unhealthy": {
                                    "http_statuses": [499]
                                }
                            },
                            "passive": {
                                "healthy": {
                                    "http_statuses": [200, 201],
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "http_statuses": [500, 600],
                                    "http_failures": 2
                                }
                            }
                        }
                    }
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
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: invalid \"maximum\" in docuement at pointer \"#\/upstream\/checks\/passive\/unhealthy\/http_statuses\/1\""}
--- no_error_log
[error]



=== TEST 6: invalid route: wrong active.type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "uri": "/index.html",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin",
                        "checks": {
                            "active": {
                                "type": "udp",
                                "healthy": {
                                    "successes": 2
                                },
                                "unhealthy": {
                                    "http_statuses": [499]
                                }
                            },
                            "passive": {
                                "healthy": {
                                    "http_statuses": [200, 201],
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "http_statuses": [500, 600],
                                    "http_failures": 2
                                }
                            }
                        }
                    }
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
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: invalid \"enum\" in docuement at pointer \"#\/upstream\/checks\/active\/type\""}
--- no_error_log
[error]



=== TEST 7: invalid route: duplicate items in active.healthy.http_statuses
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "uri": "/index.html",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin",
                        "checks": {
                            "active": {
                                "healthy": {
                                    "successes": 2,
                                    "http_statuses": [200, 200]
                                },
                                "unhealthy": {
                                    "http_statuses": [499]
                                }
                            },
                            "passive": {
                                "healthy": {
                                    "http_statuses": [200, 201],
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "http_statuses": [500, 600],
                                    "http_failures": 2
                                }
                            }
                        }
                    }
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
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: invalid \"uniqueItems\" in docuement at pointer \"#\/upstream\/checks\/active\/healthy\/http_statuses\/1\""}
--- no_error_log
[error]



=== TEST 8: invalid route: active.unhealthy.http_failure is a floating point value
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "uri": "/index.html",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8080": 1
                        },
                        "type": "roundrobin",
                        "checks": {
                            "active": {
                                "healthy": {
                                    "successes": 2,
                                    "http_statuses": [200, 200]
                                },
                                "unhealthy": {
                                    "http_statuses": [499],
                                    "http_failures": 3.1
                                }
                            },
                            "passive": {
                                "healthy": {
                                    "http_statuses": [200, 201],
                                    "successes": 1
                                },
                                "unhealthy": {
                                    "http_statuses": [500, 600],
                                    "http_failures": 2
                                }
                            }
                        }
                    }
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
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: invalid \"type\" in docuement at pointer \"#\/upstream\/checks\/active\/unhealthy\/http_failures\""}
--- no_error_log
[error]
