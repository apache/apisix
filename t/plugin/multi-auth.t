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

repeat_each(2);
no_long_string();
no_root_location();
no_shuffle();
run_tests;

__DATA__

=== TEST 1: add consumer with basic-auth and key-auth plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "bar"
                        },
                        "key-auth": {
                            "key": "auth-one"
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



=== TEST 2: enable multi auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "multi-auth": {
                            "auth_plugins": [
                                {
                                    "basic-auth": {}
                                },
                                {
                                    "key-auth": {
                                        "query": "apikey",
                                        "hide_credentials": true,
                                        "header": "apikey"
                                    }
                                },
                                {
                                    "jwt-auth": {
                                        "cookie": "jwt",
                                        "query": "jwt",
                                        "hide_credentials": true,
                                        "header": "authorization"
                                    }
                                }
                            ]
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



=== TEST 3: verify, missing authorization
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Authorization Failed"}



=== TEST 4: verify basic-auth
--- request
GET /hello
--- more_headers
Authorization: Basic Zm9vOmJhcg==
--- response_body
hello world
--- error_log
find consumer foo



=== TEST 5: verify key-auth
--- request
GET /hello
--- more_headers
apikey: auth-one
--- response_body
hello world



=== TEST 6: verify, invalid basic credentials
--- request
GET /hello
--- more_headers
Authorization: Basic YmFyOmJhcgo=
--- error_code: 401
--- response_body
{"message":"Authorization Failed"}



=== TEST 7: verify, invalid api key
--- request
GET /hello
--- more_headers
apikey: auth-two
--- error_code: 401
--- response_body
{"message":"Authorization Failed"}



=== TEST 8: enable multi auth plugin with invalid plugin conf in first auth_plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "multi-auth": {
                            "auth_plugins": [
                                {
                                    "basic-auth": {
                                        "hide_credentials": "false"
                                    }
                                },
                                {
                                    "key-auth": {}
                                },
                                {
                                    "jwt-auth": {}
                                }
                            ]
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
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin multi-auth err: plugin basic-auth check schema failed: property \"hide_credentials\" validation failed: wrong type: expected boolean, got string"}



=== TEST 9: enable multi auth plugin with invalid plugin conf in second auth_plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "multi-auth": {
                            "auth_plugins": [
                                {
                                    "key-auth": {}
                                },
                                {
                                    "basic-auth": "blah"
                                },
                                {
                                    "jwt-auth": {}
                                }
                            ]
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
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin multi-auth err: plugin basic-auth check schema failed: wrong type: expected object, got string"}



=== TEST 10: enable multi auth plugin with invalid plugin conf in third auth_plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "multi-auth": {
                            "auth_plugins": [
                                {
                                    "key-auth": {}
                                },
                                {
                                    "basic-auth": {}
                                },
                                {
                                    "jwt-auth": {
                                        "header": 123
                                    }
                                }
                            ]
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
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin multi-auth err: plugin jwt-auth check schema failed: property \"header\" validation failed: wrong type: expected string, got number"}



=== TEST 11: enable multi auth plugin with default plugin conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "multi-auth": {
                            "auth_plugins": [
                                {
                                    "basic-auth": {}
                                },
                                {
                                    "key-auth": {}
                                },
                                {
                                    "jwt-auth": {}
                                }
                            ]
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



=== TEST 12: verify, missing authorization
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Authorization Failed"}



=== TEST 13: verify basic-auth
--- request
GET /hello
--- more_headers
Authorization: Basic Zm9vOmJhcg==
--- response_body
hello world
--- error_log
find consumer foo



=== TEST 14: verify key-auth
--- request
GET /hello
--- more_headers
apikey: auth-one
--- response_body
hello world



=== TEST 15: verify, invalid basic credentials
--- request
GET /hello
--- more_headers
Authorization: Basic YmFyOmJhcgo=
--- error_code: 401
--- response_body
{"message":"Authorization Failed"}



=== TEST 16: verify, invalid api key
--- request
GET /hello
--- more_headers
apikey: auth-two
--- error_code: 401
--- response_body
{"message":"Authorization Failed"}



=== TEST 17: enable multi auth plugin using admin api, without any auth_plugins configuration
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "multi-auth": { }
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
--- error_code: 400
--- response_body_like eval
qr/\{"error_msg":"failed to check the configuration of plugin multi-auth err: property \\"auth_plugins\\" is required"\}/



=== TEST 18: enable multi auth plugin using admin api, with auth_plugins configuration but with one authorization plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "multi-auth": {
                            "auth_plugins": [
                                {
                                    "basic-auth": {}
                                }
                            ]
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
--- error_code: 400
--- response_body_like eval
qr/\{"error_msg":"failed to check the configuration of plugin multi-auth err: property \\"auth_plugins\\" validation failed: expect array to have at least 2 items"\}/



=== TEST 20: add consumer with username and jwt-auth plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "jwt-auth": {
                            "key": "user-key",
                            "secret": "my-secret-key"
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



=== TEST 22: verify multi-auth with plugin config will cause the conf_version change
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, err = t('/apisix/admin/plugin_configs/1',
                ngx.HTTP_PUT,
                [[{
                    "desc": "Multiple Authentication",
                    "plugins": {
                        "multi-auth": {
                            "auth_plugins": [
                                {
                                    "basic-auth": {}
                                },
                                {
                                    "key-auth": {
                                        "query": "apikey",
                                        "hide_credentials": true,
                                        "header": "apikey"
                                    }
                                },
                                {
                                    "jwt-auth": {
                                        "cookie": "jwt",
                                        "query": "jwt",
                                        "hide_credentials": true,
                                        "header": "authorization"
                                    }
                                }
                            ]
                        }
                    }
                  }]]
            )
            if code > 300 then
                ngx.log(ngx.ERR, err)
                return
            end

            local code, err = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugin_config_id": 1
                }]]
            )
            if code > 300 then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.sleep(0.1)

            local code, _, res = t('/hello?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJrZXkiOiJ1c2VyLWtleSIsImV4cCI6MTg3OTMxODU0MX0.fNtFJnNmJgzbiYmGB0Yjvm-l6A6M4jRV1l4mnVFSYjs',
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- request
GET /t
--- response_body
hello world
