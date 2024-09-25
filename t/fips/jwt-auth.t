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

=== TEST 1: add consumer with username and plugins with public_key
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
                            "public_key": "-----BEGIN PUBLIC KEY-----\nMFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr\n7noq/0ukiZqVQLSJPMOv0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQ==\n-----END PUBLIC KEY-----"
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



=== TEST 2: JWT sign and verify use RS256 algorithm
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



=== TEST 3: sign/verify use RS256 algorithm(private_key numbits = 512)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- private_key = "-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJBAKebDxlvQMGyEesAL1r1nIJBkSdqu3Hr7noq/0ukiZqVQLSJPMOv\n0oxQSutvvK3hoibwGakDOza+xRITB7cs2cECAwEAAQJAYPWh6YvjwWobVYC45Hz7\n+pqlt1DWeVQMlN407HSWKjdH548ady46xiQuZ5Cfx3YyCcnsfVWaQNbC+jFbY4YL\nwQIhANfASwz8+2sKg1xtvzyaChX5S5XaQTB+azFImBJumixZAiEAxt93Td6JH1RF\nIeQmD/K+DClZMqSrliUzUqJnCPCzy6kCIAekDsRh/UF4ONjAJkKuLedDUfL3rNFb\n2M4BBSm58wnZAiEAwYLMOg8h6kQ7iMDRcI9I8diCHM8yz0SfbfbsvzxIFxECICXs\nYvIufaZvBa8f+E/9CANlVhm5wKAyM8N8GJsiCyEG\n-----END RSA PRIVATE KEY-----"

            local sign = "eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1Gd3dEUVlKS29aSWh2Y05BUUVCQlFBRFN3QXdTQUpCQUtlYkR4bHZRTUd5RWVzQUwxcjFuSUpCa1NkcXUzSHJcbjdub3EvMHVraVpxVlFMU0pQTU92MG94UVN1dHZ2SzNob2lid0dha0RPemEreFJJVEI3Y3MyY0VDQXdFQUFRPT1cbi0tLS0tRU5EIFBVQkxJQyBLRVktLS0tLSJdLCJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYmYiOjE3MjcyNzQ5ODMsImtleSI6InVzZXIta2V5LXJzMjU2In0.Vrw0-Z6hYa8unzgxOjYv4U59LqhwYuefsZ2N5GSfJG5dbOrR4Dnk2tA8MNvTonKt4ShAvrGyTBuqWlbpubArrQ"
            local code, _, res = t('/hello?jwt=' .. sign,
                ngx.HTTP_GET
            )

            ngx.status = code
        }
    }
--- error_code: 401
--- error_log
JWT token invalid: invalid jwt string



=== TEST 4: add consumer with username and plugins with public_key
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
                            "public_key": "-----BEGIN PUBLIC KEY-----\nMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDGxOfVe/seP5T/V8pkS5YNAPRC\n3Ffxxedi7v0pyZh/4d4p9Qx0P9wOmALwlOq4Ftgks311pxG0zL0LcTJY4ikbc3r0\nh8SM0yhj9UV1VGtuia4YakobvpM9U+kq3lyIMO9ZPRez0cP3AJIYCt5yf8E7bNYJ\njbJNjl8WxvM1tDHqVQIDAQAB\n-----END PUBLIC KEY-----"
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



=== TEST 5: JWT sign and verify use RS256 algorithm
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



=== TEST 6: sign/verify use RS256 algorithm(private_key numbits = 1024)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- private_key = "-----BEGIN RSA PRIVATE KEY-----\nMIICXQIBAAKBgQDGxOfVe/seP5T/V8pkS5YNAPRC3Ffxxedi7v0pyZh/4d4p9Qx0\nP9wOmALwlOq4Ftgks311pxG0zL0LcTJY4ikbc3r0h8SM0yhj9UV1VGtuia4Yakob\nvpM9U+kq3lyIMO9ZPRez0cP3AJIYCt5yf8E7bNYJjbJNjl8WxvM1tDHqVQIDAQAB\nAoGAYFy9eAXvLC7u8QuClzT9vbgksvVXvWKQVqo+GbAeOoEpz3V5YDJFYN3ZLwFC\n+ZQ5nTFXNV6Veu13CMEMA4NBIa8I4r3aYzSjq7X7UEBkLDBtEUge52mYakNfXD8D\nqViHkyJqvtVnBl7jNZVqbBderQnXA0kigaeZPL3+hkYKBgECQQDmiDbUL3FBynLy\nNX6/JdAbO4g1Nl/1RsGg8svhb6vRM8WQyIQWt5EKi7yoP/9nIRXcIgdwpVO6wZRU\nDojL0oy1AkEA3LpjqXxIRzcy2ALsqKN3hoNPGAlkPyG3Mlph91mqSZ2jYpXCX9LW\nhhQdf9GmfO8jZtYhYAJqEMOJrKeZHToLIQJBAJbrJbnTNTn05ztZehh5ELxDRPBR\nIJDaOXi8emyjRsA2PGiEXLTih7l3sZIUE4fYSQ9L18MO+LmScSB2Q2fr9uECQFc7\nIh/dCgN7ARD1Nun+kEIMqrlpHMEGZgv0RDsoqG+naOaRINwVysn6MR5OkGlXaLo/\nbbkvuxMc88/T/GLciYECQQC4oUveCOic4Qs6TQfMUKKv/kJ09slbD70HkcBzA5nY\nyro4RT4z/SN6T3SD+TuWn2//I5QxiQEIbOCTySci7yuh\n-----END RSA PRIVATE KEY-----"

            local sign = "eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1JR2ZNQTBHQ1NxR1NJYjNEUUVCQVFVQUE0R05BRENCaVFLQmdRREd4T2ZWZS9zZVA1VC9WOHBrUzVZTkFQUkNcbjNGZnh4ZWRpN3YwcHlaaC80ZDRwOVF4MFA5d09tQUx3bE9xNEZ0Z2tzMzExcHhHMHpMMExjVEpZNGlrYmMzcjBcbmg4U00weWhqOVVWMVZHdHVpYTRZYWtvYnZwTTlVK2txM2x5SU1POVpQUmV6MGNQM0FKSVlDdDV5ZjhFN2JOWUpcbmpiSk5qbDhXeHZNMXRESHFWUUlEQVFBQlxuLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tIl0sImFsZyI6IlJTMjU2IiwidHlwIjoiSldUIn0.eyJuYmYiOjE3MjcyNzQ5ODMsImtleSI6InVzZXIta2V5LXJzMjU2In0.gIXtrAzmKBZ1ekySR9loFXWyed9up4xy0k51ZWjG3JFet_sOyKGnika9X2c91yAn7n_K1x7DJR_WgAbR8D_knm9J3CoAvZzy2ODfqLrPZWSqXuQH8qxPeqrlHQPQdEUN7EBRm23gg3pFg7gmHeKNJQUjUNhQFzfNXZfJgYo1bM8"
            local code, _, res = t('/hello?jwt=' .. sign,
                ngx.HTTP_GET
            )

            ngx.status = code
        }
    }
--- error_code: 401
--- error_log
JWT token invalid: invalid jwt string



=== TEST 7: sign/verify use RS256 algorithm(private_key numbits = 1024,with extra payload)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- private_key = "-----BEGIN RSA PRIVATE KEY-----\nMIICXQIBAAKBgQDGxOfVe/seP5T/V8pkS5YNAPRC3Ffxxedi7v0pyZh/4d4p9Qx0\nP9wOmALwlOq4Ftgks311pxG0zL0LcTJY4ikbc3r0h8SM0yhj9UV1VGtuia4Yakob\nvpM9U+kq3lyIMO9ZPRez0cP3AJIYCt5yf8E7bNYJjbJNjl8WxvM1tDHqVQIDAQAB\nAoGAYFy9eAXvLC7u8QuClzT9vbgksvVXvWKQVqo+GbAeOoEpz3V5YDJFYN3ZLwFC\n+ZQ5nTFXNV6Veu13CMEMA4NBIa8I4r3aYzSjq7X7UEBkLDBtEUge52mYakNfXD8D\nqViHkyJqvtVnBl7jNZVqbBderQnXA0kigaeZPL3+hkYKBgECQQDmiDbUL3FBynLy\nNX6/JdAbO4g1Nl/1RsGg8svhb6vRM8WQyIQWt5EKi7yoP/9nIRXcIgdwpVO6wZRU\nDojL0oy1AkEA3LpjqXxIRzcy2ALsqKN3hoNPGAlkPyG3Mlph91mqSZ2jYpXCX9LW\nhhQdf9GmfO8jZtYhYAJqEMOJrKeZHToLIQJBAJbrJbnTNTn05ztZehh5ELxDRPBR\nIJDaOXi8emyjRsA2PGiEXLTih7l3sZIUE4fYSQ9L18MO+LmScSB2Q2fr9uECQFc7\nIh/dCgN7ARD1Nun+kEIMqrlpHMEGZgv0RDsoqG+naOaRINwVysn6MR5OkGlXaLo/\nbbkvuxMc88/T/GLciYECQQC4oUveCOic4Qs6TQfMUKKv/kJ09slbD70HkcBzA5nY\nyro4RT4z/SN6T3SD+TuWn2//I5QxiQEIbOCTySci7yuh\n-----END RSA PRIVATE KEY-----"
            -- payload = {"aaa":"11","bb":"222"}

            local sign = "eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1JR2ZNQTBHQ1NxR1NJYjNEUUVCQVFVQUE0R05BRENCaVFLQmdRREd4T2ZWZS9zZVA1VC9WOHBrUzVZTkFQUkNcbjNGZnh4ZWRpN3YwcHlaaC80ZDRwOVF4MFA5d09tQUx3bE9xNEZ0Z2tzMzExcHhHMHpMMExjVEpZNGlrYmMzcjBcbmg4U00weWhqOVVWMVZHdHVpYTRZYWtvYnZwTTlVK2txM2x5SU1POVpQUmV6MGNQM0FKSVlDdDV5ZjhFN2JOWUpcbmpiSk5qbDhXeHZNMXRESHFWUUlEQVFBQlxuLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tIl0sInR5cCI6IkpXVCIsImFsZyI6IlJTMjU2In0.eyJhYWEiOiIxMSIsImJiIjoiMjIyIiwibmJmIjoxNzI3Mjc0OTgzLCJrZXkiOiJ1c2VyLWtleS1yczI1NiJ9.MYxhZUK_vohfFJcqaZZtFXTXkNXPDnDPe6wfAv2ILAqZC4zbMWabpfa_CCXJXqhJXRlh4R1cy1GyfO_MC5MQPE6Gl7Ykb37sKoTUgUqtqirFjq4si8nJ49WXvbuaAVSxessfNanCA9oeV7CqRn75_vO8kliDNGiim8ZOjaOSFRg"
            local code, _, res = t('/hello?jwt=' .. sign,
                ngx.HTTP_GET
            )

            ngx.status = code
        }
    }
--- error_code: 401
--- error_log
JWT token invalid: invalid jwt string
