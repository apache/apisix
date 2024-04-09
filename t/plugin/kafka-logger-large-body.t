use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    my $http_config = $block->http_config // <<_EOC_;
    # fake server, only for test
    server {
        listen 1970;
        location /large_resp {
            content_by_lua_block {
                local large_body = {
                    "h", "e", "l", "l", "o"
                }

                local size_in_bytes = 1024 * 1024 -- 1mb
                for i = 1, size_in_bytes do
                    large_body[i+5] = "l"
                end
                large_body = table.concat(large_body, "")

                ngx.say(large_body)
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests;

__DATA__


=== TEST 1: max_body_bytes is not an integer
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.kafka-logger")
            local ok, err = plugin.check_schema({
                broker_list= {
                    ["127.0.0.1"] = 9092
                },
                kafka_topic = "test2",
                key = "key1",
                timeout = 1,
                batch_max_size = 1,
                max_req_body_bytes = "10",
                include_req_body = true,
                meta_format = "origin"
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
property "max_req_body_bytes" validation failed: wrong type: expected integer, got string
done


=== TEST 2: set route(meta_format = origin, include_req_body = true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "kafka-logger": {
                                "broker_list" : {
                                    "127.0.0.1":9092
                                },
                                "kafka_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "batch_max_size": 1,
                                "max_req_body_bytes": 5,
                                "include_req_body": true,
                                "meta_format": "origin"
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
--- response_body
passed


=== TEST 3: hit route(meta_format = origin, include_req_body = true)
--- request
GET /hello?ab=cd
abcdef
--- response_body
hello world
--- error_log
send data to kafka: GET /hello?ab=cd HTTP/1.1
host: localhost
content-length: 6
connection: close
abcde
--- wait: 2


=== TEST 4: set route(meta_format = default, include_req_body = true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "kafka-logger": {
                                "broker_list" : {
                                    "127.0.0.1":9092
                                },
                                "kafka_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "batch_max_size": 1,
                                "max_req_body_bytes": 5,
                                "include_req_body": true
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
--- response_body
passed


=== TEST 5: hit route(meta_format = default, include_req_body = true)
--- request
GET /hello?ab=cd
abcdef
--- response_body
hello world
--- error_log_like eval
qr/"body": "abcde"/
--- wait: 2


=== TEST 6: set route(id: 1, meta_format = default, include_resp_body = true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "kafka-logger": {
                                "broker_list" :
                                  {
                                    "127.0.0.1":9092
                                  },
                                "kafka_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "max_resp_body_bytes": 5,
                                "include_resp_body": true,
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]=]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }

--- response_body
passed


=== TEST 7: hit route(meta_format = default, include_resp_body = true)
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- error_log eval
qr/send data to kafka: \{.*"body":"hello"/
--- wait: 2



=== TEST 8: set route(id: 1, meta_format = origin, include_resp_body = true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "kafka-logger": {
                                "broker_list" :
                                  {
                                    "127.0.0.1":9092
                                  },
                                "kafka_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "meta_format": "origin",
                                "include_resp_body": true,
                                "max_resp_body_bytes": 5,
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]=]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }

--- response_body
passed


=== TEST 9: hit route(meta_format = origin, include_resp_body = true)
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- error_log
send data to kafka: POST /hello?name=qwerty HTTP/1.1
host: localhost
content-length: 6
connection: close
--- wait: 2


=== TEST 10: set route(id: 1, meta_format = default, include_resp_body = true, include_req_body = true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "kafka-logger": {
                                "broker_list" :
                                  {
                                    "127.0.0.1":9092
                                  },
                                "kafka_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "meta_format": "default",
                                "include_req_body": true,
                                "max_req_body_bytes": 5,
                                "include_resp_body": true,
                                "max_resp_body_bytes": 5,
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]=]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }

--- response_body
passed


=== TEST 11: hit route(meta_format = default, include_resp_body = true, include_req_body = true)
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- error_log eval
qr/send data to kafka: \{.*"body":"abcde"/
--- error_log_like
*"body":"hello"
--- wait: 2



=== TEST 12: set route(id: 1, meta_format = default, include_resp_body = false, include_req_body = false)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "kafka-logger": {
                                "broker_list" :
                                  {
                                    "127.0.0.1":9092
                                  },
                                "kafka_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "meta_format": "default",
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]=]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }

--- response_body
passed


=== TEST 13: hit route(meta_format = default, include_resp_body = false, include_req_body = false)
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- no_error_log eval
qr/send data to kafka: \{.*"body":.*/
--- wait: 2



=== TEST 14: set route(large_body, meta_format = default, include_resp_body = true, include_req_body = true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "kafka-logger": {
                                "broker_list" :
                                  {
                                    "127.0.0.1":9092
                                  },
                                "kafka_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "meta_format": "default",
                                "include_req_body": true,
                                "max_req_body_bytes": 256,
                                "include_resp_body": true,
                                "max_resp_body_bytes": 256,
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/echo"
                }]=]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }

--- response_body
passed



=== TEST 15: hit route(large_body, meta_format = default, include_resp_body = true, include_req_body = true)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t    = require("lib.test_admin")
            local http = require("resty.http")

            local large_body = {
                "h", "e", "l", "l", "o"
            }

            local size_in_bytes = 10 * 1024 -- 10kb
            for i = 1, size_in_bytes do
                large_body[i+5] = "l"
            end
            large_body = table.concat(large_body, "")

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/echo"

            local httpc = http.new()
            local res, err = httpc:request_uri(uri,
                {
                    method = "POST",
                    body = large_body,
                }
            )
            ngx.say(res.body)
        }
    }
--- request
GET /t
--- error_log eval
qr/send data to kafka: \{.*"body":"hello(l{251})".*/
--- response_body eval
qr/hello.*/



=== TEST 16: set route(large_body, meta_format = default, include_resp_body = true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "kafka-logger": {
                                "broker_list" :
                                  {
                                    "127.0.0.1":9092
                                  },
                                "kafka_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "meta_format": "default",
                                "include_resp_body": true,
                                "max_resp_body_bytes": 256,
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/echo"
                }]=]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }

--- response_body
passed



=== TEST 17: hit route(large_body, meta_format = default, include_resp_body = true)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t    = require("lib.test_admin")
            local http = require("resty.http")

            local large_body = {
                "h", "e", "l", "l", "o"
            }

            local size_in_bytes = 10 * 1024 -- 10kb
            for i = 1, size_in_bytes do
                large_body[i+5] = "l"
            end
            large_body = table.concat(large_body, "")

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/echo"

            local httpc = http.new()
            local res, err = httpc:request_uri(uri,
                {
                    method = "POST",
                    body = large_body,
                }
            )
            ngx.say(res.body)
        }
    }
--- request
GET /t
--- error_log eval
qr/send data to kafka: \{.*"body":"hello(l{251})".*/
--- response_body eval
qr/hello.*/



=== TEST 18: set route(large_body, meta_format = default, include_req_body = true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "kafka-logger": {
                                "broker_list" :
                                  {
                                    "127.0.0.1":9092
                                  },
                                "kafka_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "meta_format": "default",
                                "include_req_body": true,
                                "max_req_body_bytes": 256,
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/echo"
                }]=]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }

--- response_body
passed



=== TEST 19: hit route(large_body, meta_format = default, include_req_body = true)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t    = require("lib.test_admin")
            local http = require("resty.http")

            local large_body = {
                "h", "e", "l", "l", "o"
            }

            local size_in_bytes = 10 * 1024 -- 10kb
            for i = 1, size_in_bytes do
                large_body[i+5] = "l"
            end
            large_body = table.concat(large_body, "")

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/echo"

            local httpc = http.new()
            local res, err = httpc:request_uri(uri,
                {
                    method = "POST",
                    body = large_body,
                }
            )
            ngx.say(res.body)
        }
    }
--- request
GET /t
--- error_log eval
qr/send data to kafka: \{.*"body":"hello(l{251})".*/
--- response_body eval
qr/hello.*/



=== TEST 20: set route(large_body, meta_format = default, include_resp_body = true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "kafka-logger": {
                                "broker_list" :
                                  {
                                    "127.0.0.1":9092
                                  },
                                "kafka_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "meta_format": "default",
                                "include_resp_body": true,
                                "max_resp_body_bytes": 256,
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1970": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/large_resp"
                }]=]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }

--- response_body
passed



=== TEST 21: truncate upstream response body 1m to 256 bytes
--- request
GET /large_resp
--- response_body eval
qr/hello.*/
--- error_log eval
qr/send data to kafka: \{.*"body":"hello(l{251})".*/



=== TEST 22: set route(large_body, meta_format = default, include_req_body = true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "plugins": {
                            "kafka-logger": {
                                "broker_list" :
                                  {
                                    "127.0.0.1":9092
                                  },
                                "kafka_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "meta_format": "default",
                                "include_req_body": true,
                                "max_req_body_bytes": 256,
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]=]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }

--- response_body
passed



=== TEST 23: truncate upstream request body 1m to 256 bytes
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t    = require("lib.test_admin")
            local http = require("resty.http")

            local large_body = {
                "h", "e", "l", "l", "o"
            }

            local size_in_bytes = 100 * 1024 -- 10kb
            for i = 1, size_in_bytes do
                large_body[i+5] = "l"
            end
            large_body = table.concat(large_body, "")

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            local httpc = http.new()
            local res, err = httpc:request_uri(uri,
                {
                    method = "GET",
                    body = large_body,
                }
            )

            if err then
                ngx.say(err)
            end

            ngx.say(res.body)
        }
    }
--- request
GET /t
--- response_body_like
hello world
--- error_log eval
qr/send data to kafka: \{.*"body":"hello(l{251})".*/



=== TEST 24: set route(meta_format = default, include_req_body = true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "kafka-logger": {
                                "broker_list" : {
                                    "127.0.0.1":9092
                                },
                                "kafka_topic" : "test2",
                                "key" : "key1",
                                "timeout" : 1,
                                "batch_max_size": 1,
                                "max_req_body_bytes": 5,
                                "include_req_body": true,
                                "meta_format": "default"
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
--- response_body
passed


=== TEST 25: fail to get body_file with empty request body
--- request
GET /hello?ab=cd
--- response_body
hello world
--- error_log
fail to get body_file
--- wait: 2
