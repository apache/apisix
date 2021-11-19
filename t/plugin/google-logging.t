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
run_tests;


add_block_preprocessor(sub {
    my ($block) = @_;

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

__DATA__

=== TEST 1: Full configuration verification (Auth File)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.google-logging")
            local ok, err = plugin.check_schema({
                auth_file = "/path/to/apache/apisix/auth.json",
                resource = {
                    type = "global"
                },
                scopes = {
                    "https://www.googleapis.com/auth/logging.admin"
                },
                log_id = "syslog",
                max_retry_count = 0,
                retry_delay = 1,
                buffer_duration = 60,
                inactive_timeout = 10,
                batch_max_size = 100,
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: Full configuration verification (Auth Config)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.google-logging")
            local ok, err = plugin.check_schema({
                auth_config = {
                    private_key = "private_key",
                    project_id = "apisix",
                    token_uri = "http://127.0.0.1:1980/token",
                },
                resource = {
                    type = "global"
                },
                scopes = {
                    "https://www.googleapis.com/auth/logging.admin"
                },
                log_id = "syslog",
                max_retry_count = 0,
                retry_delay = 1,
                buffer_duration = 60,
                inactive_timeout = 10,
                batch_max_size = 100,
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 3: Basic configuration verification (Auth File)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.google-logging")
            local ok, err = plugin.check_schema({
                auth_file = "/path/to/apache/apisix/auth.json",
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 4: Basic configuration verification (Auth Config)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.google-logging")
            local ok, err = plugin.check_schema({
                auth_config = {
                    private_key = "private_key",
                    project_id = "apisix",
                    token_uri = "http://127.0.0.1:1980/token",
                },
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: auth configure undefined
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.google-logging")
            local ok, err = plugin.check_schema({
                log_id = "syslog",
                max_retry_count = 0,
                retry_delay = 1,
                buffer_duration = 60,
                inactive_timeout = 10,
                batch_max_size = 100,
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- request
GET /t
--- response_body
value should match only one schema, but matches none
--- no_error_log
[error]



=== TEST 6: set route (identity authentication failed)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT, [[
                    {
                        "uri":"/hello",
                        "upstream":{
                            "type":"roundrobin",
                            "nodes":{
                                "127.0.0.1:1980":1
                            }
                        },
                        "plugins":{
                            "google-logging":{
                                "auth_config":{
                                    "private_key": "-----BEGIN RSA PRIVATE KEY-----\nMIIBOwIBAAJBAKeXgPvU/dAfVhOPk5BTBXCaOXy/0S3mY9VHyqvWZBJ97g6tGbLZ\npsn6Gw0wC4mxDfEY5ER4YwU1NWCVtIr1XxcCAwEAAQJADkoowVBD4/8IA9r2JhQu\nHo/H3w8r8tH2KTVZ3pUFK15WGJf8vCF9LznVNKCP0X1NMLGvf4yRELx8jjpwJztI\ngQIhANdWaJ3AGftJNaF5qXWwniFP1BcyCPSzn3q0rn19NhyHAiEAxz0HN8Yd+7vR\npi0w/L2I/2nLqgPFtqSGpL2KkJYcXPECIQCdM/PD1k4haNzCOXNA++M1JnYLSPfI\nzKkMh4MrEZHDWQIhAKasRiKBaUnTCIJ04bs9L6NDtO4Ic9jj8ANW0Nk9yoJxAiAA\ntBXLQH7fw5H8RaxBN91yQUZombw6JnRBXKKohWHZ3Q==\n-----END RSA PRIVATE KEY-----",
                                    "project_id":"apisix",
                                    "token_uri":"http://127.0.0.1:1980/google/logging/token",
                                    "scopes": [
                                        "https://apisix.apache.org/logs:admin"
                                    ],
                                    "entries_uri":"http://127.0.0.1:1980/google/logging/entries"
                                },
                                "inactive_timeout":1,
                                "batch_max_size":1
                            }
                        }
                     }
                 ]])

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
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



=== TEST 7: test route (identity authentication failed)
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- grep_error_log eval
qr/\{\"error\"\:\"[\w+\s+]*\"\}/
--- grep_error_log_out
{"error":"identity authentication failed"}



=== TEST 8: set route (no access to this scopes)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT, [[
                    {
                        "uri":"/hello",
                        "upstream":{
                            "type":"roundrobin",
                            "nodes":{
                                "127.0.0.1:1980":1
                            }
                        },
                        "plugins":{
                            "google-logging":{
                                "auth_config":{
                                    "private_key": "-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr7noq/0ukiZqVQLSJPMOv\n0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQJAYPWh6YvjwWobVYC45Hz7\n+pqlt1DWeVQMlN407HSWKjdH548ady46xiQuZ5Cfx3YyCcnsfVWaQNbC+jFbY4YL\nwQIhANfASwz8+2sKg1xtvzyaChX5S5XaQTB+azFImBJumixZAiEAxt93Td6JH1RF\nIeQmD/K+DClZMqSrliUzUqJnCPCzy6kCIAekDsRh/UF4ONjAJkKuLedDUfL3rNFb\n2M4BBSm58wnZAiEAwYLMOg8h6kQ7iMDRcI9I8diCHM8yz0SfbfbsvzxIFxECICXs\nYvIufaZvBa8f+E/9CANlVhm5wKAyM8N8GJsiCyEG\n-----END RSA PRIVATE KEY-----",
                                    "project_id":"apisix",
                                    "token_uri":"http://127.0.0.1:1980/google/logging/token",
                                    "entries_uri":"http://127.0.0.1:1980/google/logging/entries"
                                },
                                "inactive_timeout":1,
                                "batch_max_size":1
                            }
                        }
                     }
                 ]])

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
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



=== TEST 9: test route (no access to this scopes)
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- grep_error_log eval
qr/\{\"error\"\:\"[\w+\s+]*\"\}/
--- grep_error_log_out
{"error":"no access to this scopes"}



=== TEST 10: set route (succeed write)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT, [[
                    {
                        "uri":"/hello",
                        "upstream":{
                            "type":"roundrobin",
                            "nodes":{
                                "127.0.0.1:1980":1
                            }
                        },
                        "plugins":{
                            "google-logging":{
                                "auth_config":{
                                    "private_key": "-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr7noq/0ukiZqVQLSJPMOv\n0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQJAYPWh6YvjwWobVYC45Hz7\n+pqlt1DWeVQMlN407HSWKjdH548ady46xiQuZ5Cfx3YyCcnsfVWaQNbC+jFbY4YL\nwQIhANfASwz8+2sKg1xtvzyaChX5S5XaQTB+azFImBJumixZAiEAxt93Td6JH1RF\nIeQmD/K+DClZMqSrliUzUqJnCPCzy6kCIAekDsRh/UF4ONjAJkKuLedDUfL3rNFb\n2M4BBSm58wnZAiEAwYLMOg8h6kQ7iMDRcI9I8diCHM8yz0SfbfbsvzxIFxECICXs\nYvIufaZvBa8f+E/9CANlVhm5wKAyM8N8GJsiCyEG\n-----END RSA PRIVATE KEY-----",
                                    "project_id":"apisix",
                                    "token_uri":"http://127.0.0.1:1980/google/logging/token",
                                    "scopes": [
                                        "https://apisix.apache.org/logs:admin"
                                    ],
                                    "entries_uri":"http://127.0.0.1:1980/google/logging/entries"
                                },
                                "inactive_timeout":1,
                                "batch_max_size":1
                            }
                        }
                     }
                 ]])

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
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



=== TEST 11: test route(succeed write)
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- no_error_log
[error]
