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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__


=== TEST 2: add consumer with username and plugins with public_key, private_key(private_key numbits = 512)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "kerouac",
                    "plugins": {
                        "jwt-auth": {
                            "key": "user-key-rs256",
                            "algorithm": "RS256",
                            "public_key": "-----BEGIN PUBLIC KEY-----\nMFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr\n7noq/0ukiZqVQLSJPMOv0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQ==\n-----END PUBLIC KEY-----",
                            "private_key": "-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr7noq/0ukiZqVQLSJPMOv\n0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQJAYPWh6YvjwWobVYC45Hz7\n+pqlt1DWeVQMlN407HSWKjdH548ady46xiQuZ5Cfx3YyCcnsfVWaQNbC+jFbY4YL\nwQIhANfASwz8+2sKg1xtvzyaChX5S5XaQTB+azFImBJumixZAiEAxt93Td6JH1RF\nIeQmD/K+DClZMqSrliUzUqJnCPCzy6kCIAekDsRh/UF4ONjAJkKuLedDUfL3rNFb\n2M4BBSm58wnZAiEAwYLMOg8h6kQ7iMDRcI9I8diCHM8yz0SfbfbsvzxIFxECICXs\nYvIufaZvBa8f+E/9CANlVhm5wKAyM8N8GJsiCyEG\n-----END RSA PRIVATE KEY-----"
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
--- response_body
passed



=== TEST 3: JWT sign and verify use RS256 algorithm(private_key numbits = 512)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {}
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



=== TEST 4: sign/verify use RS256 algorithm(private_key numbits = 512)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local gen_token = require("apisix.plugins.jwt-auth").gen_token

            local key = "user-key-rs256"
            local consumer = {
                auth_conf = {
                    key = "user-key-rs256",
                    algorithm = "RS256",
                    public_key = "-----BEGIN PUBLIC KEY-----\nMFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr\n7noq/0ukiZqVQLSJPMOv0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQ==\n-----END PUBLIC KEY-----",
                    private_key = "-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr7noq/0ukiZqVQLSJPMOv\n0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQJAYPWh6YvjwWobVYC45Hz7\n+pqlt1DWeVQMlN407HSWKjdH548ady46xiQuZ5Cfx3YyCcnsfVWaQNbC+jFbY4YL\nwQIhANfASwz8+2sKg1xtvzyaChX5S5XaQTB+azFImBJumixZAiEAxt93Td6JH1RF\nIeQmD/K+DClZMqSrliUzUqJnCPCzy6kCIAekDsRh/UF4ONjAJkKuLedDUfL3rNFb\n2M4BBSm58wnZAiEAwYLMOg8h6kQ7iMDRcI9I8diCHM8yz0SfbfbsvzxIFxECICXs\nYvIufaZvBa8f+E/9CANlVhm5wKAyM8N8GJsiCyEG\n-----END RSA PRIVATE KEY-----"
                }
            }
            local sign = gen_token(key, nil, consumer)
            if not sign then
                ngx.status = 404
                ngx.say("failed to gen_token")
                return
            end

            local code, _, res = t('/hello?jwt=' .. sign,
                ngx.HTTP_GET
            )

            ngx.status = code
        }
    }
--- error_code: 401
--- error_log
JWT token invalid: invalid jwt string



=== TEST 5: add consumer with username and plugins with public_key, private_key(private_key numbits = 1024)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "kerouac",
                    "plugins": {
                        "jwt-auth": {
                            "key": "user-key-rs256",
                            "algorithm": "RS256",
                            "public_key": "-----BEGIN PUBLIC KEY-----\nMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDGxOfVe/seP5T/V8pkS5YNAPRC\n3Ffxxedi7v0pyZh/4d4p9Qx0P9wOmALwlOq4Ftgks311pxG0zL0LcTJY4ikbc3r0\nh8SM0yhj9UV1VGtuia4YakobvpM9U+kq3lyIMO9ZPRez0cP3AJIYCt5yf8E7bNYJ\njbJNjl8WxvM1tDHqVQIDAQAB\n-----END PUBLIC KEY-----",
                            ]] .. [[
                            "private_key": "-----BEGIN RSA PRIVATE KEY-----\nMIICXQIBAAKBgQDGxOfVe/seP5T/V8pkS5YNAPRC3Ffxxedi7v0pyZh/4d4p9Qx0\nP9wOmALwlOq4Ftgks311pxG0zL0LcTJY4ikbc3r0h8SM0yhj9UV1VGtuia4Yakob\nvpM9U+kq3lyIMO9ZPRez0cP3AJIYCt5yf8E7bNYJjbJNjl8WxvM1tDHqVQIDAQAB\nAoGAYFy9eAXvLC7u8QuClzT9vbgksvVXvWKQVqo+GbAeOoEpz3V5YDJFYN3ZLwFC\n+ZQ5nTFXNV6Veu13CMEMA4NBIa8I4r3aYzSjq7X7UEBkLDBtEUge52mYakNfXD8D\nqViHkyJqvtVnBl7jNZVqbBderQnXA0kigaeZPL3+hkYKBgECQQDmiDbUL3FBynLy\nNX6/JdAbO4g1Nl/1RsGg8svhb6vRM8WQyIQWt5EKi7yoP/9nIRXcIgdwpVO6wZRU\nDojL0oy1AkEA3LpjqXxIRzcy2ALsqKN3hoNPGAlkPyG3Mlph91mqSZ2jYpXCX9LW\nhhQdf9GmfO8jZtYhYAJqEMOJrKeZHToLIQJBAJbrJbnTNTn05ztZehh5ELxDRPBR\nIJDaOXi8emyjRsA2PGiEXLTih7l3sZIUE4fYSQ9L18MO+LmScSB2Q2fr9uECQFc7\nIh/dCgN7ARD1Nun+kEIMqrlpHMEGZgv0RDsoqG+naOaRINwVysn6MR5OkGlXaLo/\nbbkvuxMc88/T/GLciYECQQC4oUveCOic4Qs6TQfMUKKv/kJ09slbD70HkcBzA5nY\nyro4RT4z/SN6T3SD+TuWn2//I5QxiQEIbOCTySci7yuh\n-----END RSA PRIVATE KEY-----"
                            }
                        }
                    }
                ]]
                )
            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 6: JWT sign and verify use RS256 algorithm(private_key numbits = 1024)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "jwt-auth": {}
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



=== TEST 7: sign/verify use RS256 algorithm(private_key numbits = 1024)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local gen_token = require("apisix.plugins.jwt-auth").gen_token

            local key = "user-key-rs256"
            local consumer = {
                auth_conf = {
                    key = "user-key-rs256",
                    algorithm = "RS256",
                    public_key = "-----BEGIN PUBLIC KEY-----\nMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDGxOfVe/seP5T/V8pkS5YNAPRC\n3Ffxxedi7v0pyZh/4d4p9Qx0P9wOmALwlOq4Ftgks311pxG0zL0LcTJY4ikbc3r0\nh8SM0yhj9UV1VGtuia4YakobvpM9U+kq3lyIMO9ZPRez0cP3AJIYCt5yf8E7bNYJ\njbJNjl8WxvM1tDHqVQIDAQAB\n-----END PUBLIC KEY-----",
                    private_key = "-----BEGIN RSA PRIVATE KEY-----\nMIICXQIBAAKBgQDGxOfVe/seP5T/V8pkS5YNAPRC3Ffxxedi7v0pyZh/4d4p9Qx0\nP9wOmALwlOq4Ftgks311pxG0zL0LcTJY4ikbc3r0h8SM0yhj9UV1VGtuia4Yakob\nvpM9U+kq3lyIMO9ZPRez0cP3AJIYCt5yf8E7bNYJjbJNjl8WxvM1tDHqVQIDAQAB\nAoGAYFy9eAXvLC7u8QuClzT9vbgksvVXvWKQVqo+GbAeOoEpz3V5YDJFYN3ZLwFC\n+ZQ5nTFXNV6Veu13CMEMA4NBIa8I4r3aYzSjq7X7UEBkLDBtEUge52mYakNfXD8D\nqViHkyJqvtVnBl7jNZVqbBderQnXA0kigaeZPL3+hkYKBgECQQDmiDbUL3FBynLy\nNX6/JdAbO4g1Nl/1RsGg8svhb6vRM8WQyIQWt5EKi7yoP/9nIRXcIgdwpVO6wZRU\nDojL0oy1AkEA3LpjqXxIRzcy2ALsqKN3hoNPGAlkPyG3Mlph91mqSZ2jYpXCX9LW\nhhQdf9GmfO8jZtYhYAJqEMOJrKeZHToLIQJBAJbrJbnTNTn05ztZehh5ELxDRPBR\nIJDaOXi8emyjRsA2PGiEXLTih7l3sZIUE4fYSQ9L18MO+LmScSB2Q2fr9uECQFc7\nIh/dCgN7ARD1Nun+kEIMqrlpHMEGZgv0RDsoqG+naOaRINwVysn6MR5OkGlXaLo/\nbbkvuxMc88/T/GLciYECQQC4oUveCOic4Qs6TQfMUKKv/kJ09slbD70HkcBzA5nY\nyro4RT4z/SN6T3SD+TuWn2//I5QxiQEIbOCTySci7yuh\n-----END RSA PRIVATE KEY-----"
                }
            }
            local sign = gen_token(key, nil, consumer)
            if not sign then
                ngx.status = 404
                ngx.say("failed to gen_token")
                return
            end

            local code, _, res = t('/hello?jwt=' .. sign,
                ngx.HTTP_GET
            )

            ngx.status = code
        }
    }
--- error_code: 401
--- error_log
JWT token invalid: invalid jwt string



=== TEST 8: sign/verify use RS256 algorithm(private_key numbits = 1024,with extra payload)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local gen_token = require("apisix.plugins.jwt-auth").gen_token

            local key = "user-key-rs256"
            local payload = ngx.unescape_uri("%7B%22aaa%22%3A%2211%22%2C%22bb%22%3A%22222%22%7D") -- {"aaa":"11","bb":"222"}
            local consumer = {
                auth_conf = {
                    key = "user-key-rs256",
                    algorithm = "RS256",
                    public_key = "-----BEGIN PUBLIC KEY-----\nMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDGxOfVe/seP5T/V8pkS5YNAPRC\n3Ffxxedi7v0pyZh/4d4p9Qx0P9wOmALwlOq4Ftgks311pxG0zL0LcTJY4ikbc3r0\nh8SM0yhj9UV1VGtuia4YakobvpM9U+kq3lyIMO9ZPRez0cP3AJIYCt5yf8E7bNYJ\njbJNjl8WxvM1tDHqVQIDAQAB\n-----END PUBLIC KEY-----",
                    private_key = "-----BEGIN RSA PRIVATE KEY-----\nMIICXQIBAAKBgQDGxOfVe/seP5T/V8pkS5YNAPRC3Ffxxedi7v0pyZh/4d4p9Qx0\nP9wOmALwlOq4Ftgks311pxG0zL0LcTJY4ikbc3r0h8SM0yhj9UV1VGtuia4Yakob\nvpM9U+kq3lyIMO9ZPRez0cP3AJIYCt5yf8E7bNYJjbJNjl8WxvM1tDHqVQIDAQAB\nAoGAYFy9eAXvLC7u8QuClzT9vbgksvVXvWKQVqo+GbAeOoEpz3V5YDJFYN3ZLwFC\n+ZQ5nTFXNV6Veu13CMEMA4NBIa8I4r3aYzSjq7X7UEBkLDBtEUge52mYakNfXD8D\nqViHkyJqvtVnBl7jNZVqbBderQnXA0kigaeZPL3+hkYKBgECQQDmiDbUL3FBynLy\nNX6/JdAbO4g1Nl/1RsGg8svhb6vRM8WQyIQWt5EKi7yoP/9nIRXcIgdwpVO6wZRU\nDojL0oy1AkEA3LpjqXxIRzcy2ALsqKN3hoNPGAlkPyG3Mlph91mqSZ2jYpXCX9LW\nhhQdf9GmfO8jZtYhYAJqEMOJrKeZHToLIQJBAJbrJbnTNTn05ztZehh5ELxDRPBR\nIJDaOXi8emyjRsA2PGiEXLTih7l3sZIUE4fYSQ9L18MO+LmScSB2Q2fr9uECQFc7\nIh/dCgN7ARD1Nun+kEIMqrlpHMEGZgv0RDsoqG+naOaRINwVysn6MR5OkGlXaLo/\nbbkvuxMc88/T/GLciYECQQC4oUveCOic4Qs6TQfMUKKv/kJ09slbD70HkcBzA5nY\nyro4RT4z/SN6T3SD+TuWn2//I5QxiQEIbOCTySci7yuh\n-----END RSA PRIVATE KEY-----"
                }
            }

            local sign = gen_token(key, payload, consumer)
            if not sign then
                ngx.status = 404
                ngx.say("failed to gen_token")
                return
            end

            local code, _, res = t('/hello?jwt=' .. sign,
                ngx.HTTP_GET
            )

            ngx.status = code
        }
    }
--- error_code: 401
--- error_log
JWT token invalid: invalid jwt string
