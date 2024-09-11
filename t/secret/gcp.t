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
log_level("info");

run_tests;

__DATA__

=== TEST 1: sanity: validate different schema situation
--- config
    location /t {
        content_by_lua_block {
            local test_case = {
                {},
                {auth_file = "123"},
                {auth_file = 123},
                {auth_config = {client_email = "client", private_key = "private_key"}},
                {auth_config = {private_key = "private_key", project_id = "project_id"}},
                {auth_config = {client_email = "client", project_id = "project_id"}},
                {auth_config = {client_email = "client", private_key = "private_key", project_id = "project_id"}},
                {auth_config = {client_email = 1234, private_key = "private_key", project_id = "project_id"}},
                {auth_config = {client_email = "client", private_key = 1234, project_id = "project_id"}},
                {auth_config = {client_email = "client", private_key = "private_key", project_id = 1234}},
                {auth_config = {client_email = "client", private_key = "private_key", project_id = "project_id"}, ssl_verify = 1234},
                {auth_config = {client_email = "client", private_key = "private_key", project_id = "project_id", token_uri = 1234}},
                {auth_config = {client_email = "client", private_key = "private_key", project_id = "project_id", scope = 1234}},
                {auth_config = {client_email = "client", private_key = "private_key", project_id = "project_id", entries_uri = 1234}},
                {auth_config = {client_email = "client", private_key = "private_key", project_id = "project_id", token_uri = "token_uri",
                    scope = {"scope"}, entries_uri = "entries_uri"}, ssl_verify = true},
            }
            local gcp = require("apisix.secret.gcp")
            local core = require("apisix.core")
            local metadata_schema = gcp.schema

            for _, conf in ipairs(test_case) do
                local ok, err = core.schema.check(metadata_schema, conf)
                ngx.say(ok and "done" or err)
            end
        }
    }
--- request
GET /t
--- response_body
value should match only one schema, but matches none
done
property "auth_file" validation failed: wrong type: expected string, got number
property "auth_config" validation failed: property "project_id" is required
property "auth_config" validation failed: property "client_email" is required
property "auth_config" validation failed: property "private_key" is required
done
property "auth_config" validation failed: property "client_email" validation failed: wrong type: expected string, got number
property "auth_config" validation failed: property "private_key" validation failed: wrong type: expected string, got number
property "auth_config" validation failed: property "project_id" validation failed: wrong type: expected string, got number
property "ssl_verify" validation failed: wrong type: expected boolean, got number
property "auth_config" validation failed: property "token_uri" validation failed: wrong type: expected string, got number
property "auth_config" validation failed: property "scope" validation failed: wrong type: expected array, got number
property "auth_config" validation failed: property "entries_uri" validation failed: wrong type: expected string, got number
done



=== TEST 2: check key: no main key
--- config
    location /t {
        content_by_lua_block {
            local gcp = require("apisix.secret.gcp")
            local conf = {
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
                    token_uri = "http://127.0.0.1:1980/token",
                    scope = {
                        "https://www.googleapis.com/auth/cloud-platform"
                    },
                },
            }
            local data, err = gcp.get(conf, "/apisix")
            if err then
                return ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
can't find main key, key: /apisix



=== TEST 3: add secret  && consumer && check
--- request
GET /t
--- config
    location /t {
        content_by_lua_block {
            local conf = {
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
                    token_uri = "http://127.0.0.1:1980/google/secret/token",
                    scope = {
                        "https://www.googleapis.com/auth/cloud-platform"
                    },
                    entries_uri = "http://127.0.0.1:1984"
                },
            }

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/secrets/gcp/mysecret', ngx.HTTP_PUT, conf)

            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            -- change consumer with secrets ref: gcp
            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                          "key-auth": {
                            "key": "$secret://gcp/mysecret/jack/key"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end


            local secret = require("apisix.secret")
            local value = secret.fetch_by_uri("$secret://gcp/mysecret/jack/key")


            local code, body = t('/apisix/admin/secrets/gcp/mysecret', ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                          "key-auth": {
                            "key": "$secret://gcp/mysecret/jack/key"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            local secret = require("apisix.secret")
            local value = secret.fetch_by_uri("$secret://gcp/mysecret/jack/key")
            if value then
                ngx.say("secret value: ", value)
            end
            ngx.say("all done")
        }
    }
--- response_body
all done



=== TEST 4: setup route (/projects/apisix/secrets/jack/versions/latest:access)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions": [
                                "return function(conf, ctx)
                                    require('lib.server').google_secret_apisix_jack()
                                end"
                            ]
                        }
                    },
                    "uri": "/projects/apisix/secrets/jack/versions/latest:access",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
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



=== TEST 5: setup route (/projects/apisix_error/secrets/jack/versions/latest:access)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions": [
                                "return function(conf, ctx)
                                    require('lib.server').google_secret_apisix_error_jack()
                                end"
                            ]
                        }
                    },
                    "uri": "/projects/apisix_error/secrets/jack/versions/latest:access",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
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



=== TEST 6: setup route (/projects/apisix/secrets/mysql/versions/latest:access)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/3',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions": [
                                "return function(conf, ctx)
                                    require('lib.server').google_secret_apisix_mysql()
                                end"
                            ]
                        }
                    },
                    "uri": "/projects/apisix/secrets/mysql/versions/latest:access",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
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



=== TEST 7: get value from gcp by auth_file(fetch_oatuh_conf failed, read failed)
--- config
    location /t {
        content_by_lua_block {
            local conf = {
                auth_file = "t/secret/conf/nofind.json",
            }
            local gcp = require("apisix.secret.gcp")
            local value, err = gcp.get(conf, "jack/key")
            if not value then
                return ngx.say(err)
            end
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
failed to retrtive data from gcp secret manager: failed to read configuration, file: t/secret/conf/nofind.json, err: t/secret/conf/nofind.json: No such file or directory



=== TEST 8: get value from gcp by auth_file(fetch_oatuh_conf success)
--- config
    location /t {
        content_by_lua_block {
            local conf = {
                auth_file = "t/secret/conf/success.json",
            }
            local gcp = require("apisix.secret.gcp")
            local value, err = gcp.get(conf, "jack/key")
            if not value then
                return ngx.say(err)
            end
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
value



=== TEST 9: get value from gcp by auth_file(fetch_oatuh_conf failed, undefined)
--- config
    location /t {
        content_by_lua_block {
            local conf = {
                auth_file = "t/secret/conf/error.json",
            }
            local gcp = require("apisix.secret.gcp")
            local value, err = gcp.get(conf, "jack/key")
            if not value then
                return ngx.say(err)
            end
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
failed to retrtive data from gcp secret manager: config parse failure, file: t/secret/conf/error.json, err: property "auth_config" validation failed: property "client_email" is required



=== TEST 10: get json value from gcp
--- config
    location /t {
        content_by_lua_block {
            local conf = {
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
                    token_uri = "http://127.0.0.1:1980/google/secret/token",
                    scope = {
                        "https://www.googleapis.com/auth/cloud-platform"
                    },
                    entries_uri = "http://127.0.0.1:1984"
                },
            }
            local gcp = require("apisix.secret.gcp")
            local value, err = gcp.get(conf, "jack/key")
            if not value then
                return ngx.say(err)
            end
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
value



=== TEST 11: get string value from gcp
--- config
    location /t {
        content_by_lua_block {
            local conf = {
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
                    token_uri = "http://127.0.0.1:1980/google/secret/token",
                    scope = {
                        "https://www.googleapis.com/auth/cloud-platform"
                    },
                    entries_uri = "http://127.0.0.1:1984"
                },
            }
            local gcp = require("apisix.secret.gcp")
            local value, err = gcp.get(conf, "mysql")
            if not value then
                return ngx.say(err)
            end
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
secret



=== TEST 12: get value from gcp(failed to get google oauth token)
--- config
    location /t {
        content_by_lua_block {
            local conf = {
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
                    token_uri = "http://127.0.0.1:1980/google/secret/token",
                    scope = {
                        "https://www.googleapis.com/auth/root/cloud-platform"
                    },
                    entries_uri = "http://127.0.0.1:1984"
                },
            }
            local gcp = require("apisix.secret.gcp")
            local value, err = gcp.get(conf, "jack/key")
            if not value then
                return ngx.say(err)
            end
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
failed to retrtive data from gcp secret manager: failed to get google oauth token
--- grep_error_log eval
qr/\{\"error\"\:\"[\w+\s+]*\"\}/
--- grep_error_log_out
{"error":"no access to this scope"}



=== TEST 13: get value from gcp (not res)
--- config
    location /t {
        content_by_lua_block {
            local conf = {
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
                    project_id = "apisix_error",
                    token_uri = "http://127.0.0.1:1980/google/secret/token",
                    scope = {
                        "https://www.googleapis.com/auth/cloud-platform"
                    },
                    entries_uri = "http://127.0.0.1:1984"
                },
            }
            local gcp = require("apisix.secret.gcp")
            local value, err = gcp.get(conf, "jack/key")
            if not value then
                return ngx.say("err")
            end
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
err



=== TEST 14: get value from gcp (res status ~= 200)
--- config
    location /t {
        content_by_lua_block {
            local conf = {
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
                    project_id = "apisix_error",
                    token_uri = "http://127.0.0.1:1980/google/secret/token",
                    scope = {
                        "https://www.googleapis.com/auth/cloud-platform"
                    },
                    entries_uri = "http://127.0.0.1:1984"
                },
            }
            local gcp = require("apisix.secret.gcp")
            local value, err = gcp.get(conf, "jack/key")
            if not value then
                return ngx.say("err")
            end
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
err
