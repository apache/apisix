use t::APISIX 'no_plan';

log_level("info");
repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: set route(default value: port and timeout)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 3,
                            "time_window": 6,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "sync_interval": 5
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
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



=== TEST 2: send 5 request only 3 get accepted
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200, 503, 503]
--- response_headers eval
[
    "X-RateLimit-Remaining: 2",
    "X-RateLimit-Remaining: 1",
    "X-RateLimit-Remaining: 0",
    "X-RateLimit-Remaining: 0",
    "X-RateLimit-Remaining: 0"
]



=== TEST 3: send request and wait for 5 seconds (because sync_interval = 5), check logs
--- request
GET /hello
--- error_code: 200
--- wait: 5
--- error_log
syncing shdict num_req counter to redis



=== TEST 4: create route with sync_interval = -1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 3,
                            "time_window": 6,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "sync_interval": -1
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
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



=== TEST 5: send request and wait for 5 seconds... no delayed sync logs
--- request
GET /hello
--- error_code: 200
--- wait: 5
--- no_error_log
syncing shdict num_req counter to redis



=== TEST 6: count = 1, time_window = 3, sync_interval = 5
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 1,
                            "time_window": 3,
                            "rejected_code": 504,
                            "key": "remote_addr",
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "sync_interval": 5
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
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



=== TEST 7: send 2 requests, 1st passes, 2nd fails
--- pipelined_requests eval
["GET /hello", "GET /hello"]
--- error_code eval
[200, 504]



=== TEST 8: wait for counter reset after two requests and retry
--- config
    location /t {
        content_by_lua_block {
            local json = require "t.toolkit.json"
            local http = require "resty.http"
            local httpc = http.new()

            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local ress = {}
            for i = 1, 2 do
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(ress, res.status)
            end
            ngx.sleep(3)
            for i = 1, 2 do
                local res, err = httpc:request_uri(uri)
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(ress, res.status)
            end
            ngx.say(json.encode(ress))
        }
    }
--- response_body
[200,504,200,504]
