use t::APISix 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    my $init_by_lua_block = <<_EOC_;
    require "resty.core"
    apisix = require("apisix")
    apisix.http_init()

    json = require("cjson.safe")
    req_data = json.decode([[{
        "methods": ["GET"],
        "upstream": {
            "nodes": {
                "127.0.0.1:8080": 1
            },
            "type": "roundrobin",
            "checks": {}
        },
        "uri": "/index.html"
    }]])
    exp_data = {
        node = {
            value = req_data,
            key = "/apisix/routes/1",
        },
        action = "set",
    }
_EOC_

    $block->set_value("init_by_lua_block", $init_by_lua_block);
});

run_tests;

__DATA__

=== TEST 1: active
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            req_data.upstream.checks = json.decode([[{
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
            }]])
            exp_data.node.value.upstream.checks = req_data.upstream.checks

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                req_data,
                exp_data
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

            req_data.upstream.checks = json.decode([[{
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
            }]])
            exp_data.node.value.upstream.checks = req_data.upstream.checks

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                req_data,
                exp_data
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

            req_data.upstream.checks = json.decode([[{
                "active": {
                    "healthy": {
                        "successes": 255
                    }
                }
            }]])

            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, req_data)

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

            req_data.upstream.checks = json.decode([[{
                "active": {
                    "healthy": {
                        "successes": 0
                    }
                }
            }]])

            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, req_data)

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

            req_data.upstream.checks = json.decode([[{
                "passive": {
                    "unhealthy": {
                        "http_statuses": [500, 600]
                    }
                }
            }]])

            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, req_data)

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

            req_data.upstream.checks = json.decode([[{
                "active": {
                    "type": "udp"
                }
            }]])

            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, req_data)

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

            req_data.upstream.checks = json.decode([[{
                "active": {
                    "healthy": {
                        "http_statuses": [200, 200]
                    }
                }
            }]])

            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, req_data)

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

            req_data.upstream.checks = json.decode([[{
                "active": {
                    "unhealthy": {
                        "http_failures": 3.1
                    }
                }
            }]])

            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, req_data)

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
