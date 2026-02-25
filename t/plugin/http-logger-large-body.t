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
            local plugin = require("apisix.plugins.http-logger")
            local ok, err = plugin.check_schema({
                uri = "http://127.0.0.1:12001/http-logger/center",
                timeout = 1,
                batch_max_size = 1,
                max_req_body_bytes = "10",
                include_req_body = true
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



=== TEST 2: max_resp_body_bytes is not an integer
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.http-logger")
            local ok, err = plugin.check_schema({
                uri = "http://127.0.0.1:12001/http-logger/center",
                timeout = 1,
                batch_max_size = 1,
                max_resp_body_bytes = "10",
                include_resp_body = true
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
property "max_resp_body_bytes" validation failed: wrong type: expected integer, got string
done



=== TEST 3: set route(include_req_body = true, concat_method = json)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "http-logger": {
                            "uri": "http://127.0.0.1:12001/http-logger/center",
                            "timeout": 1,
                            "batch_max_size": 1,
                            "max_req_body_bytes": 5,
                            "include_req_body": true,
                            "concat_method": "json"
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



=== TEST 4: hit route(include_req_body = true, concat_method = json)
--- request
POST /hello?ab=cd
abcdef
--- response_body
hello world
--- error_log_like eval
qr/"body": "abcde"/
--- wait: 2



=== TEST 5: set route(include_resp_body = true, concat_method = json)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "plugins": {
                        "http-logger": {
                            "uri": "http://127.0.0.1:12001/http-logger/center",
                            "timeout": 1,
                            "max_resp_body_bytes": 5,
                            "include_resp_body": true,
                            "batch_max_size": 1,
                            "concat_method": "json"
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



=== TEST 6: hit route(include_resp_body = true, concat_method = json)
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- error_log eval
qr/received http log: \{.*"body":"hello"/
--- wait: 2



=== TEST 7: set route(include_resp_body = true, include_req_body = true, concat_method = json)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "plugins": {
                        "http-logger": {
                            "uri": "http://127.0.0.1:12001/http-logger/center",
                            "timeout": 1,
                            "include_req_body": true,
                            "max_req_body_bytes": 5,
                            "include_resp_body": true,
                            "max_resp_body_bytes": 5,
                            "batch_max_size": 1,
                            "concat_method": "json"
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



=== TEST 8: hit route(include_resp_body = true, include_req_body = true, concat_method = json)
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- error_log eval
qr/received http log: \{.*"body":"abcde"/
--- error_log_like
*"body":"hello"
--- wait: 2



=== TEST 9: set route(include_resp_body = false, include_req_body = false)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "plugins": {
                        "http-logger": {
                            "uri": "http://127.0.0.1:12001/http-logger/center",
                            "timeout": 1,
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



=== TES 10: hit route(include_resp_body = false, include_req_body = false)
--- request
POST /hello?name=qwerty
abcdef
--- response_body
hello world
--- no_error_log eval
qr/received http log: \{.*"body":.*/
--- wait: 2



=== TEST 11: set route(large_body, include_resp_body = true, include_req_body = true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "plugins": {
                        "http-logger": {
                            "uri": "http://127.0.0.1:12001/http-logger/center",
                            "timeout": 1,
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



=== TEST 12: hit route(large_body, include_resp_body = true, include_req_body = true)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")
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
qr/received http log: \{.*"body":"hello(l{251})".*/
--- response_body eval
qr/hello.*/



=== TEST 13: set route(large_body, include_resp_body = true)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [=[{
                    "plugins": {
                        "http-logger": {
                            "uri": "http://127.0.0.1:12001/http-logger/center",
                            "timeout": 1,
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



=== TEST 14: hit route(large_body, include_resp_body = true)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")
            local http = require("resty.http")

            local large_body = {
                "h", "e", "l", "l", "o"
            }

            local size_in_bytes = 10 * 1024 -- 10kb
            local i = 1, size_in_bytes do
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
qr/received http log: \{.*"body":"hello(l{251})".*/
--- response_body eval
qr/hello.*/