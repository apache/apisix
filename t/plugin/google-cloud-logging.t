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

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

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
                    client_email = "email@apisix.iam.gserviceaccount.com",
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
                    client_email = "email@apisix.iam.gserviceaccount.com",
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
                            client_email = "email@apisix.iam.gserviceaccount.com",
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
                            client_email = "email@apisix.iam.gserviceaccount.com",
                            private_key = [[
-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDDzrFwnA3EvYyR
aeMgaLD3hBjvxKrz10uox1X8q7YYhf2ViRtLRUMa2bEMYksE5hbhwpNf6mKAnLOC
UuAT6cPPdUl/agKpJXviBPIR2LuzD17WsLJHp1HxUDssSkgfCaGcOGGNfLUhhIpF
2JUctLmxiZoAZySlSjcwupSuDJ0aPm0XO8r9H8Qu5kF2Vkz5e5bFivLTmvzrQTe4
v5V1UI6hThElCSeUmdNF3uG3wopxlvq4zXgLTnuLbrNf/Gc4mlpV+UDgTISj32Ep
AB2vxKEbvQw4ti8YJnGXWjxLerhfrszFw+V8lpeduiDYA44ZFoVqvzxeIsVZNtcw
Iu7PvEPNAgMBAAECggEAVpyN9m7A1F631/aLheFpLgMbeKt4puV7zQtnaJ2XrZ9P
PR7pmNDpTu4uF3k/D8qrIm+L+uhVa+hkquf3wDct6w1JVnfQ93riImbnoKdK13ic
DcEZCwLjByfjFMNCxZ/gAZca55fbExlqhFy6EHmMjhB8s2LsXcTHRuGxNI/Vyi49
sxECibe0U53aqdJbVWrphIS67cpwl4TUkN6mrHsNuDYNJ9dgkpapoqp4FTFQsBqC
afOK5qgJ68dWZ47FBUng+AZjdCncqAIuJxxItGVQP6YPsFs+OXcivIVHJr363TpC
l85FfdvqWV5OGBbwSKhNwiTNUVvfSQVmtURGWG/HbQKBgQD4gZ1z9+Lx19kT9WTz
lw93lxso++uhAPDTKviyWSRoEe5aN3LCd4My+/Aj+sk4ON/s2BV3ska5Im93j+vC
rCv3uPn1n2jUhWuJ3bDqipeTW4n/CQA2m/8vd26TMk22yOkkqw2MIA8sjJ//SD7g
tdG7up6DgGMP4hgbO89uGU7DAwKBgQDJtkKd0grh3u52Foeh9YaiAgYRwc65IE16
UyD1OJxIuX/dYQDLlo5KyyngFa1ZhWIs7qC7r3xXH+10kfJY+Q+5YMjmZjlL8SR1
Ujqd02R9F2//6OeswyReachJZbZdtiEw3lPa4jVFYfhSe0M2ZPxMwvoXb25eyCNI
1lYjSKq87wKBgHnLTNghjeDp4UKe6rNYPgRm0rDrhziJtX5JeUov1mALKb6dnmkh
GfRK9g8sQqKDfXwfC6Z2gaMK9YaryujGaWYoCpoPXtmJ6oLPXH4XHuLh4mhUiP46
xn8FEfSimuQS4/FMxH8A128GHQSI7AhGFFzlwfrBWcvXC+mNDsTvMmLxAoGARc+4
upppfccETQZ7JsitMgD1TMwA2f2eEwoWTAitvlXFNT9PYSbYVHaAJbga6PLLCbYF
FzAjHpxEOKYSdEyu7n/ayDL0/Z2V+qzc8KarDsg/0RgwppBbU/nUgeKb/U79qcYo
y4ai3UKNCS70Ei1dTMvmdpnwXwlxfNIBufB6dy0CgYBMYq9Lc31GkC6PcGEEbx6W
vjImOadWZbuOVnvEQjb5XCdcOsWsMcg96PtoeuyyHmhnEF1GsMzcIdQv/PHrvYpK
Yp8D0aqsLEgwGrJQER26FPpKmyIwvcL+nm6q5W31PnU9AOC/WEkB6Zs58hsMzD2S
kEJQcmfVew5mFXyxuEn3zA==
-----END PRIVATE KEY-----]],
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
                            client_email = "email@apisix.iam.gserviceaccount.com",
                            private_key = [[
-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDDzrFwnA3EvYyR
aeMgaLD3hBjvxKrz10uox1X8q7YYhf2ViRtLRUMa2bEMYksE5hbhwpNf6mKAnLOC
UuAT6cPPdUl/agKpJXviBPIR2LuzD17WsLJHp1HxUDssSkgfCaGcOGGNfLUhhIpF
2JUctLmxiZoAZySlSjcwupSuDJ0aPm0XO8r9H8Qu5kF2Vkz5e5bFivLTmvzrQTe4
v5V1UI6hThElCSeUmdNF3uG3wopxlvq4zXgLTnuLbrNf/Gc4mlpV+UDgTISj32Ep
AB2vxKEbvQw4ti8YJnGXWjxLerhfrszFw+V8lpeduiDYA44ZFoVqvzxeIsVZNtcw
Iu7PvEPNAgMBAAECggEAVpyN9m7A1F631/aLheFpLgMbeKt4puV7zQtnaJ2XrZ9P
PR7pmNDpTu4uF3k/D8qrIm+L+uhVa+hkquf3wDct6w1JVnfQ93riImbnoKdK13ic
DcEZCwLjByfjFMNCxZ/gAZca55fbExlqhFy6EHmMjhB8s2LsXcTHRuGxNI/Vyi49
sxECibe0U53aqdJbVWrphIS67cpwl4TUkN6mrHsNuDYNJ9dgkpapoqp4FTFQsBqC
afOK5qgJ68dWZ47FBUng+AZjdCncqAIuJxxItGVQP6YPsFs+OXcivIVHJr363TpC
l85FfdvqWV5OGBbwSKhNwiTNUVvfSQVmtURGWG/HbQKBgQD4gZ1z9+Lx19kT9WTz
lw93lxso++uhAPDTKviyWSRoEe5aN3LCd4My+/Aj+sk4ON/s2BV3ska5Im93j+vC
rCv3uPn1n2jUhWuJ3bDqipeTW4n/CQA2m/8vd26TMk22yOkkqw2MIA8sjJ//SD7g
tdG7up6DgGMP4hgbO89uGU7DAwKBgQDJtkKd0grh3u52Foeh9YaiAgYRwc65IE16
UyD1OJxIuX/dYQDLlo5KyyngFa1ZhWIs7qC7r3xXH+10kfJY+Q+5YMjmZjlL8SR1
Ujqd02R9F2//6OeswyReachJZbZdtiEw3lPa4jVFYfhSe0M2ZPxMwvoXb25eyCNI
1lYjSKq87wKBgHnLTNghjeDp4UKe6rNYPgRm0rDrhziJtX5JeUov1mALKb6dnmkh
GfRK9g8sQqKDfXwfC6Z2gaMK9YaryujGaWYoCpoPXtmJ6oLPXH4XHuLh4mhUiP46
xn8FEfSimuQS4/FMxH8A128GHQSI7AhGFFzlwfrBWcvXC+mNDsTvMmLxAoGARc+4
upppfccETQZ7JsitMgD1TMwA2f2eEwoWTAitvlXFNT9PYSbYVHaAJbga6PLLCbYF
FzAjHpxEOKYSdEyu7n/ayDL0/Z2V+qzc8KarDsg/0RgwppBbU/nUgeKb/U79qcYo
y4ai3UKNCS70Ei1dTMvmdpnwXwlxfNIBufB6dy0CgYBMYq9Lc31GkC6PcGEEbx6W
vjImOadWZbuOVnvEQjb5XCdcOsWsMcg96PtoeuyyHmhnEF1GsMzcIdQv/PHrvYpK
Yp8D0aqsLEgwGrJQER26FPpKmyIwvcL+nm6q5W31PnU9AOC/WEkB6Zs58hsMzD2S
kEJQcmfVew5mFXyxuEn3zA==
-----END PRIVATE KEY-----]],
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
                            client_email = "email@apisix.iam.gserviceaccount.com",
                            private_key = [[
-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDDzrFwnA3EvYyR
aeMgaLD3hBjvxKrz10uox1X8q7YYhf2ViRtLRUMa2bEMYksE5hbhwpNf6mKAnLOC
UuAT6cPPdUl/agKpJXviBPIR2LuzD17WsLJHp1HxUDssSkgfCaGcOGGNfLUhhIpF
2JUctLmxiZoAZySlSjcwupSuDJ0aPm0XO8r9H8Qu5kF2Vkz5e5bFivLTmvzrQTe4
v5V1UI6hThElCSeUmdNF3uG3wopxlvq4zXgLTnuLbrNf/Gc4mlpV+UDgTISj32Ep
AB2vxKEbvQw4ti8YJnGXWjxLerhfrszFw+V8lpeduiDYA44ZFoVqvzxeIsVZNtcw
Iu7PvEPNAgMBAAECggEAVpyN9m7A1F631/aLheFpLgMbeKt4puV7zQtnaJ2XrZ9P
PR7pmNDpTu4uF3k/D8qrIm+L+uhVa+hkquf3wDct6w1JVnfQ93riImbnoKdK13ic
DcEZCwLjByfjFMNCxZ/gAZca55fbExlqhFy6EHmMjhB8s2LsXcTHRuGxNI/Vyi49
sxECibe0U53aqdJbVWrphIS67cpwl4TUkN6mrHsNuDYNJ9dgkpapoqp4FTFQsBqC
afOK5qgJ68dWZ47FBUng+AZjdCncqAIuJxxItGVQP6YPsFs+OXcivIVHJr363TpC
l85FfdvqWV5OGBbwSKhNwiTNUVvfSQVmtURGWG/HbQKBgQD4gZ1z9+Lx19kT9WTz
lw93lxso++uhAPDTKviyWSRoEe5aN3LCd4My+/Aj+sk4ON/s2BV3ska5Im93j+vC
rCv3uPn1n2jUhWuJ3bDqipeTW4n/CQA2m/8vd26TMk22yOkkqw2MIA8sjJ//SD7g
tdG7up6DgGMP4hgbO89uGU7DAwKBgQDJtkKd0grh3u52Foeh9YaiAgYRwc65IE16
UyD1OJxIuX/dYQDLlo5KyyngFa1ZhWIs7qC7r3xXH+10kfJY+Q+5YMjmZjlL8SR1
Ujqd02R9F2//6OeswyReachJZbZdtiEw3lPa4jVFYfhSe0M2ZPxMwvoXb25eyCNI
1lYjSKq87wKBgHnLTNghjeDp4UKe6rNYPgRm0rDrhziJtX5JeUov1mALKb6dnmkh
GfRK9g8sQqKDfXwfC6Z2gaMK9YaryujGaWYoCpoPXtmJ6oLPXH4XHuLh4mhUiP46
xn8FEfSimuQS4/FMxH8A128GHQSI7AhGFFzlwfrBWcvXC+mNDsTvMmLxAoGARc+4
upppfccETQZ7JsitMgD1TMwA2f2eEwoWTAitvlXFNT9PYSbYVHaAJbga6PLLCbYF
FzAjHpxEOKYSdEyu7n/ayDL0/Z2V+qzc8KarDsg/0RgwppBbU/nUgeKb/U79qcYo
y4ai3UKNCS70Ei1dTMvmdpnwXwlxfNIBufB6dy0CgYBMYq9Lc31GkC6PcGEEbx6W
vjImOadWZbuOVnvEQjb5XCdcOsWsMcg96PtoeuyyHmhnEF1GsMzcIdQv/PHrvYpK
Yp8D0aqsLEgwGrJQER26FPpKmyIwvcL+nm6q5W31PnU9AOC/WEkB6Zs58hsMzD2S
kEJQcmfVew5mFXyxuEn3zA==
-----END PRIVATE KEY-----]],
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
                            client_email = "email@apisix.iam.gserviceaccount.com",
                            private_key = [[
-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDDzrFwnA3EvYyR
aeMgaLD3hBjvxKrz10uox1X8q7YYhf2ViRtLRUMa2bEMYksE5hbhwpNf6mKAnLOC
UuAT6cPPdUl/agKpJXviBPIR2LuzD17WsLJHp1HxUDssSkgfCaGcOGGNfLUhhIpF
2JUctLmxiZoAZySlSjcwupSuDJ0aPm0XO8r9H8Qu5kF2Vkz5e5bFivLTmvzrQTe4
v5V1UI6hThElCSeUmdNF3uG3wopxlvq4zXgLTnuLbrNf/Gc4mlpV+UDgTISj32Ep
AB2vxKEbvQw4ti8YJnGXWjxLerhfrszFw+V8lpeduiDYA44ZFoVqvzxeIsVZNtcw
Iu7PvEPNAgMBAAECggEAVpyN9m7A1F631/aLheFpLgMbeKt4puV7zQtnaJ2XrZ9P
PR7pmNDpTu4uF3k/D8qrIm+L+uhVa+hkquf3wDct6w1JVnfQ93riImbnoKdK13ic
DcEZCwLjByfjFMNCxZ/gAZca55fbExlqhFy6EHmMjhB8s2LsXcTHRuGxNI/Vyi49
sxECibe0U53aqdJbVWrphIS67cpwl4TUkN6mrHsNuDYNJ9dgkpapoqp4FTFQsBqC
afOK5qgJ68dWZ47FBUng+AZjdCncqAIuJxxItGVQP6YPsFs+OXcivIVHJr363TpC
l85FfdvqWV5OGBbwSKhNwiTNUVvfSQVmtURGWG/HbQKBgQD4gZ1z9+Lx19kT9WTz
lw93lxso++uhAPDTKviyWSRoEe5aN3LCd4My+/Aj+sk4ON/s2BV3ska5Im93j+vC
rCv3uPn1n2jUhWuJ3bDqipeTW4n/CQA2m/8vd26TMk22yOkkqw2MIA8sjJ//SD7g
tdG7up6DgGMP4hgbO89uGU7DAwKBgQDJtkKd0grh3u52Foeh9YaiAgYRwc65IE16
UyD1OJxIuX/dYQDLlo5KyyngFa1ZhWIs7qC7r3xXH+10kfJY+Q+5YMjmZjlL8SR1
Ujqd02R9F2//6OeswyReachJZbZdtiEw3lPa4jVFYfhSe0M2ZPxMwvoXb25eyCNI
1lYjSKq87wKBgHnLTNghjeDp4UKe6rNYPgRm0rDrhziJtX5JeUov1mALKb6dnmkh
GfRK9g8sQqKDfXwfC6Z2gaMK9YaryujGaWYoCpoPXtmJ6oLPXH4XHuLh4mhUiP46
xn8FEfSimuQS4/FMxH8A128GHQSI7AhGFFzlwfrBWcvXC+mNDsTvMmLxAoGARc+4
upppfccETQZ7JsitMgD1TMwA2f2eEwoWTAitvlXFNT9PYSbYVHaAJbga6PLLCbYF
FzAjHpxEOKYSdEyu7n/ayDL0/Z2V+qzc8KarDsg/0RgwppBbU/nUgeKb/U79qcYo
y4ai3UKNCS70Ei1dTMvmdpnwXwlxfNIBufB6dy0CgYBMYq9Lc31GkC6PcGEEbx6W
vjImOadWZbuOVnvEQjb5XCdcOsWsMcg96PtoeuyyHmhnEF1GsMzcIdQv/PHrvYpK
Yp8D0aqsLEgwGrJQER26FPpKmyIwvcL+nm6q5W31PnU9AOC/WEkB6Zs58hsMzD2S
kEJQcmfVew5mFXyxuEn3zA==
-----END PRIVATE KEY-----]],
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



=== TEST 25: test route(https file configuration SSL authentication succeed: ssl_verify = false)
--- request
GET /hello
--- wait: 2
--- response_body
hello world
