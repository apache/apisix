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

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
     my $http_config = $block->http_config // <<_EOC_;
server {
        listen 12001;

        location /google-cloud-logging/test {
            content_by_lua_block {
                ngx.req.read_body()
                local data = ngx.req.get_body_data()
                ngx.log(ngx.WARN, "google cloud logging request body: ", data)
                ngx.log(ngx.ERR, data)
                ngx.say('test-http-logger-response')
                ngx.log(ngx.WARN, "loggingBody:", data)
            }
        }


        location /google/logging/entries {
            content_by_lua_block {
                ngx.req.read_body()
                local body = ngx.req.get_body_data()

                local data, err = require("cjson").decode(body)
                if err then
                    ngx.log(ngx.WARN, "loggingBody", body)
                end

                ngx.log(ngx.WARN, "loggingBody", body)
                ngx.say("ok")
                 ngx.print(body)
            }
        }

         location /google/logging/test1 {
            content_by_lua_block {
                ngx.req.read_body()
                local json_decode = require("toolkit.json").decode
                local json_encode = require("toolkit.json").encode
                local data = ngx.req.get_body_data()
                local decoded_data = json_decode(data)

                ngx.log(ngx.WARN,"gcp logs body entries: ", json_encode(decoded_data["entries"][1]["jsonPayload"]))
                ngx.say("ok")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);

my $extra_init_by_lua = <<_EOC_;
    local bpm = require("apisix.utils.batch-processor-manager")
    bpm.set_check_stale_interval(1)
_EOC_

    $block->set_value("extra_init_by_lua", $extra_init_by_lua);

});

run_tests();

__DATA__

=== TEST 1: Full configuration verification (Auth File)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.google-cloud-logging")
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
                include_req_body = false,
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
passed



=== TEST 2: Full configuration verification (Auth Config)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.google-cloud-logging")
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
--- response_body
passed



=== TEST 3: Basic configuration verification (Auth File)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.google-cloud-logging")
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
--- response_body
passed



=== TEST 4: Basic configuration verification (Auth Config)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.google-cloud-logging")
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
--- response_body
passed



=== TEST 5: auth configure undefined
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.google-cloud-logging")
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
--- response_body
value should match only one schema, but matches none



=== TEST 6: set route (identity authentication failed)
--- config
    location /t {
        content_by_lua_block {
            local config = {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    }
                },
                plugins = {
                    ["google-cloud-logging"] = {
                        auth_config = {
                            private_key = [[
-----BEGIN RSA PRIVATE KEY-----
MIIBOwIBAAJBAKeXgPvU/dAfVhOPk5BTBXCaOXy/0S3mY9VHyqvWZBJ97g6tGbLZ
psn6Gw0wC4mxDfEY5ER4YwU1NWCVtIr1XxcCAwEAAQJADkoowVBD4/8IA9r2JhQu
Ho/H3w8r8tH2KTVZ3pUFK15WGJf8vCF9LznVNKCP0X1NMLGvf4yRELx8jjpwJztI
gQIhANdWaJ3AGftJNaF5qXWwniFP1BcyCPSzn3q0rn19NhyHAiEAxz0HN8Yd+7vR
pi0w/L2I/2nLqgPFtqSGpL2KkJYcXPECIQCdM/PD1k4haNzCOXNA++M1JnYLSPfI
zKkMh4MrEZHDWQIhAKasRiKBaUnTCIJ04bs9L6NDtO4Ic9jj8ANW0Nk9yoJxAiAA
tBXLQH7fw5H8RaxBN91yQUZombw6JnRBXKKohWHZ3Q==
-----END RSA PRIVATE KEY-----]],
                            project_id = "apisix",
                            token_uri = "http://127.0.0.1:1980/google/logging/token",
                            scopes = {
                                "https://apisix.apache.org/logs:admin"
                            },
                            entries_uri = "http://127.0.0.1:1980/google/logging/entries",
                        },
                        inactive_timeout = 1,
                        batch_max_size = 1,
                    }
                }
            }
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, config)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



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
--- error_log
Batch Processor[google-cloud-logging] failed to process entries
Batch Processor[google-cloud-logging] exceeded the max_retry_count



=== TEST 8: set route (no access to this scopes)
--- config
    location /t {
        content_by_lua_block {
            local config = {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    }
                },
                plugins = {
                    ["google-cloud-logging"] = {
                        auth_config = {
                            private_key = [[
-----BEGIN RSA PRIVATE KEY-----
MIIBOgIBAAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr7noq/0ukiZqVQLSJPMOv
0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQJAYPWh6YvjwWobVYC45Hz7
+pqlt1DWeVQMlN407HSWKjdH548ady46xiQuZ5Cfx3YyCcnsfVWaQNbC+jFbY4YL
wQIhANfASwz8+2sKg1xtvzyaChX5S5XaQTB+azFImBJumixZAiEAxt93Td6JH1RF
IeQmD/K+DClZMqSrliUzUqJnCPCzy6kCIAekDsRh/UF4ONjAJkKuLedDUfL3rNFb
2M4BBSm58wnZAiEAwYLMOg8h6kQ7iMDRcI9I8diCHM8yz0SfbfbsvzxIFxECICXs
YvIufaZvBa8f+E/9CANlVhm5wKAyM8N8GJsiCyEG
-----END RSA PRIVATE KEY-----]],
                            project_id = "apisix",
                            token_uri = "http://127.0.0.1:1980/google/logging/token",
                            entries_uri = "http://127.0.0.1:1980/google/logging/entries",
                        },
                        inactive_timeout = 1,
                        batch_max_size = 1,
                    }
                }
            }
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, config)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



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
--- error_log
Batch Processor[google-cloud-logging] failed to process entries
Batch Processor[google-cloud-logging] exceeded the max_retry_count



=== TEST 10: set route (succeed write)
--- config
    location /t {
        content_by_lua_block {
            local config = {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    }
                },
                plugins = {
                    ["google-cloud-logging"] = {
                        auth_config = {
                            private_key = [[
-----BEGIN RSA PRIVATE KEY-----
MIIBOgIBAAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr7noq/0ukiZqVQLSJPMOv
0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQJAYPWh6YvjwWobVYC45Hz7
+pqlt1DWeVQMlN407HSWKjdH548ady46xiQuZ5Cfx3YyCcnsfVWaQNbC+jFbY4YL
wQIhANfASwz8+2sKg1xtvzyaChX5S5XaQTB+azFImBJumixZAiEAxt93Td6JH1RF
IeQmD/K+DClZMqSrliUzUqJnCPCzy6kCIAekDsRh/UF4ONjAJkKuLedDUfL3rNFb
2M4BBSm58wnZAiEAwYLMOg8h6kQ7iMDRcI9I8diCHM8yz0SfbfbsvzxIFxECICXs
YvIufaZvBa8f+E/9CANlVhm5wKAyM8N8GJsiCyEG
-----END RSA PRIVATE KEY-----]],
                            project_id = "apisix",
                            token_uri = "http://127.0.0.1:1980/google/logging/token",
                            scopes = {
                                "https://apisix.apache.org/logs:admin"
                            },
                            entries_uri = "http://127.0.0.1:1980/google/logging/entries",
                        },
                        inactive_timeout = 1,
                        batch_max_size = 1,
                    }
                }
            }
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, config)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: test route(succeed write)
--- request
GET /hello
--- wait: 2
--- response_body
hello world



=== TEST 12: set route (customize auth type)
--- config
    location /t {
        content_by_lua_block {
            local config = {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    }
                },
                plugins = {
                    ["google-cloud-logging"] = {
                        auth_config = {
                            private_key = [[
-----BEGIN RSA PRIVATE KEY-----
MIIBOgIBAAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr7noq/0ukiZqVQLSJPMOv
0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQJAYPWh6YvjwWobVYC45Hz7
+pqlt1DWeVQMlN407HSWKjdH548ady46xiQuZ5Cfx3YyCcnsfVWaQNbC+jFbY4YL
wQIhANfASwz8+2sKg1xtvzyaChX5S5XaQTB+azFImBJumixZAiEAxt93Td6JH1RF
IeQmD/K+DClZMqSrliUzUqJnCPCzy6kCIAekDsRh/UF4ONjAJkKuLedDUfL3rNFb
2M4BBSm58wnZAiEAwYLMOg8h6kQ7iMDRcI9I8diCHM8yz0SfbfbsvzxIFxECICXs
YvIufaZvBa8f+E/9CANlVhm5wKAyM8N8GJsiCyEG
-----END RSA PRIVATE KEY-----]],
                            project_id = "apisix",
                            token_uri = "http://127.0.0.1:1980/google/logging/token?token_type=Basic",
                            scopes = {
                                "https://apisix.apache.org/logs:admin"
                            },
                            entries_uri = "http://127.0.0.1:1980/google/logging/entries?token_type=Basic",
                        },
                        inactive_timeout = 1,
                        batch_max_size = 1,
                    }
                }
            }
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, config)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 13: test route(customize auth type)
--- request
GET /hello
--- wait: 2
--- response_body
hello world



=== TEST 14: set route (customize auth type error)
--- config
    location /t {
        content_by_lua_block {
            local config = {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    }
                },
                plugins = {
                    ["google-cloud-logging"] = {
                        auth_config = {
                            private_key = [[
-----BEGIN RSA PRIVATE KEY-----
MIIBOgIBAAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr7noq/0ukiZqVQLSJPMOv
0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQJAYPWh6YvjwWobVYC45Hz7
+pqlt1DWeVQMlN407HSWKjdH548ady46xiQuZ5Cfx3YyCcnsfVWaQNbC+jFbY4YL
wQIhANfASwz8+2sKg1xtvzyaChX5S5XaQTB+azFImBJumixZAiEAxt93Td6JH1RF
IeQmD/K+DClZMqSrliUzUqJnCPCzy6kCIAekDsRh/UF4ONjAJkKuLedDUfL3rNFb
2M4BBSm58wnZAiEAwYLMOg8h6kQ7iMDRcI9I8diCHM8yz0SfbfbsvzxIFxECICXs
YvIufaZvBa8f+E/9CANlVhm5wKAyM8N8GJsiCyEG
-----END RSA PRIVATE KEY-----]],
                            project_id = "apisix",
                            token_uri = "http://127.0.0.1:1980/google/logging/token?token_type=Basic",
                            scopes = {
                                "https://apisix.apache.org/logs:admin"
                            },
                            entries_uri = "http://127.0.0.1:1980/google/logging/entries",
                        },
                        inactive_timeout = 1,
                        batch_max_size = 1,
                    }
                }
            }
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, config)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 15: test route(customize auth type error)
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- grep_error_log eval
qr/\{\"error\"\:\"[\w+\s+]*\"\}/
--- grep_error_log_out
{"error":"identity authentication failed"}
--- error_log
Batch Processor[google-cloud-logging] failed to process entries
Batch Processor[google-cloud-logging] exceeded the max_retry_count



=== TEST 16: set route (file configuration is successful)
--- config
    location /t {
        content_by_lua_block {

            local config = {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    }
                },
                plugins = {
                    ["google-cloud-logging"] = {
                        auth_file = "t/plugin/google-cloud-logging/config.json",
                        inactive_timeout = 1,
                        batch_max_size = 1,
                    }
                }
            }
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, config)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 17: test route(file configuration is successful)
--- request
GET /hello
--- wait: 2
--- response_body
hello world



=== TEST 18: set route (file configuration is failed)
--- config
    location /t {
        content_by_lua_block {

            local config = {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    }
                },
                plugins = {
                    ["google-cloud-logging"] = {
                        auth_file = "google-cloud-logging/config.json",
                        inactive_timeout = 1,
                        batch_max_size = 1,
                    }
                }
            }
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, config)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 19: test route(file configuration is failed)
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- error_log
config.json: No such file or directory



=== TEST 20: set route (https file configuration is successful)
--- config
    location /t {
        content_by_lua_block {

            local config = {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    }
                },
                plugins = {
                    ["google-cloud-logging"] = {
                        auth_file = "t/plugin/google-cloud-logging/config-https-domain.json",
                        inactive_timeout = 1,
                        batch_max_size = 1,
                        ssl_verify = true,
                    }
                }
            }
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, config)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 21: test route(https file configuration is successful)
--- request
GET /hello
--- wait: 2
--- response_body
hello world



=== TEST 22: set route (https file configuration SSL authentication failed: ssl_verify = true)
--- config
    location /t {
        content_by_lua_block {

            local config = {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    }
                },
                plugins = {
                    ["google-cloud-logging"] = {
                        auth_file = "t/plugin/google-cloud-logging/config-https-ip.json",
                        inactive_timeout = 1,
                        batch_max_size = 1,
                        ssl_verify = true,
                    }
                }
            }
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, config)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 23: test route(https file configuration SSL authentication failed: ssl_verify = true)
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- error_log
failed to refresh google oauth access token, certificate host mismatch



=== TEST 24: set route (https file configuration SSL authentication succeed: ssl_verify = false)
--- config
    location /t {
        content_by_lua_block {

            local config = {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    }
                },
                plugins = {
                    ["google-cloud-logging"] = {
                        auth_file = "t/plugin/google-cloud-logging/config-https-ip.json",
                        inactive_timeout = 1,
                        batch_max_size = 1,
                        ssl_verify = false,
                    }
                }
            }
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, config)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 25: test route (https file configuration SSL authentication succeed: ssl_verify = false)
--- request
GET /hello
--- wait: 2
--- response_body
hello world



=== TEST 26: set include_req_body = true on route succeeds
--- config
    location /t {
        content_by_lua_block {

            local config = {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    }
                },
                plugins = {
                    ["google-cloud-logging"] = {
                        auth_file = "t/plugin/google-cloud-logging/config-https-ip.json",
                        inactive_timeout = 1,
                        batch_max_size = 1,
                        ssl_verify = false,
                        include_req_body = true,
                    }
                }
            }
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, config)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 27: set fetch request body and response body route
--- config
    location /t {
        content_by_lua_block {
            local config = {
                uri = "/google-cloud-logging/test",
                method = 'POST',
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:12001"] = 1
                    }
                },
                plugins = {
                    ["google-cloud-logging"] = {
                        auth_file = "t/plugin/google-cloud-logging/config.json",
                        inactive_timeout = 1,
                        batch_max_size = 1,
                        include_req_body = true,
                    }
                }
            }
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, config)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 28: set fetch request body and response body route
--- config
    location /t {
        content_by_lua_block {
            local config = {
                uri = "/google-cloud-logging/test",
                method = 'POST',
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:12001"] = 1
                    }
                },
                plugins = {
                    ["google-cloud-logging"] = {
                        auth_file = "t/plugin/google-cloud-logging/config.json",
                        inactive_timeout = 1,
                        batch_max_size = 1,
                        include_req_body = true,
                    }
                }
            }
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, config)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 29: check request body included in log entry
--- request
POST /google-cloud-logging/test
{"bodyItem": "something"}
--- error_log eval
qr/gcp logs body entries/
--- wait: 2
