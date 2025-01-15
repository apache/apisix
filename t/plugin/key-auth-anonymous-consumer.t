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


no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $user_yaml_config = <<_EOC_;
apisix:
  data_encryption:
    enable_encrypt_fields: false
_EOC_
    $block->set_value("yaml_config", $user_yaml_config);
});


run_tests;

__DATA__

=== TEST 1: add consumer jack and anonymous
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-one"
                        },
                        "limit-count": {
                            "count": 4,
                            "time_window": 60
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)

            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "anonymous",
                    "plugins": {
                        "limit-count": {
                            "count": 1,
                            "time_window": 60
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
passed



=== TEST 2: add key auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {
                            "anonymous_consumer": "anonymous"
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



=== TEST 3: normal consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            
            for i = 1, 5, 1 do
                local code, body = t('/hello',
                    ngx.HTTP_GET,
                    nil,
                    nil,
                    {
                        apikey = "auth-one"
                    }
                )

                if code >= 300 then
                    ngx.say("failed" .. code)
                    return
                end
                ngx.say(body .. i)
            end
        }
    }
--- request
GET /t
--- response_body
passed1
passed2
passed3
passed4
failed503



=== TEST 4: request without key-auth header will be from anonymous consumer and it will pass
--- request
GET /hello
--- response_body
hello world



=== TEST 4: request without key-auth header will be from anonymous consumer and different rate limit will apply
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 503, 503, 503]



=== TEST 5: add key auth plugin with non-existent anonymous_consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {
                            "anonymous_consumer": "not-found-anonymous"
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



=== TEST 6: anonymous-consumer configured in the route should not be found
--- request
GET /hello
--- error_code: 401
--- error_log
failed to get anonymous consumer not-found-anonymous
--- response_body
{"message":"Invalid user authorization"}
