BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISix 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();
log_level('debug');

run_tests;

__DATA__

=== TEST 1: set proto(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/proto/1',
                 ngx.HTTP_PUT,
                 [[{
                    "content" : "syntax = \"proto3\";
                      package helloworld;
                      service Greeter {
                          rpc SayHello (HelloRequest) returns (HelloReply) {}
                      }
                      message HelloRequest {
                          string name = 1;
                      }
                      message HelloReply {
                          string message = 1;
                         }"
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



=== TEST 2: set routes(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "uri": "/grpctest",
                    "service_protocol": "grpc",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.Greeter",
                            "method": "SayHello"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:50051": 1
                        }
                    }
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



=== TEST 3: hit route
--- request
GET /grpctest
--- response_body eval
qr/\{"message":"Hello "\}/
--- no_error_log
[error]



=== TEST 4: wrong service protocol
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "uri": "/grpctest",
                    "service_protocol": "asf",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.Greeter",
                            "method": "SayHello"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:50051": 1
                        }
                    }
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



=== TEST 5: wrong upstream address
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "uri": "/grpctest",
                    "service_protocol": "grpc",
                    "plugins": {
                        "grpc-transcode": {
                            "proto_id": "1",
                            "service": "helloworld.Greeter",
                            "method": "SayHello"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1970": 1
                        }
                    }
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



=== TEST 6: hit route (Connection refused)
--- request
GET /grpctest
--- response_body eval
qr/502 Bad Gateway/
--- error_log
Connection refused) while connecting to upstream
--- error_code: 502
