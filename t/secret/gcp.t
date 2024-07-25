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

=== TEST 1: check key: error format
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
                    token_uri = "http://127.0.0.1:2800/token",
                    scopes = "https://www.googleapis.com/auth/cloud-platform",
                },
            }
            local data, err = gcp.get(config, "apisix")
            if err then
                return ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
error key format, key: apisix



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
                    token_uri = "http://127.0.0.1:2800/token",
                    scopes = "https://www.googleapis.com/auth/cloud-platform",
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



=== TEST 3: check key: no sub key
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
                    token_uri = "http://127.0.0.1:2800/token",
                    scopes = "https://www.googleapis.com/auth/cloud-platform",
                },
            }
            local data, err = gcp.get(conf, "apisix/")
            if err then
                return ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
can't find sub key, key: apisix/



=== TEST 4: add secret  && consumer && check
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
                    scopes = "https://www.googleapis.com/auth/cloud-platform",
                    entries_uri = "http://127.0.0.1:2800/google/secret/"
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
            ngx.say(value)
        }
    }
--- response_body
nil



=== TEST 5: get value from gcp
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
                    scopes = "https://www.googleapis.com/auth/cloud",
                    entries_uri = "http://127.0.0.1:1980/google/secret/"
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



=== TEST 6: get value from gcp (failed to get google oauth token:no access to this scopes)
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
                    scopes = "https://www.googleapis.com/auth/root/cloud",
                    entries_uri = "http://127.0.0.1:1980/google/secret/"
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
{"error":"no access to this scopes"}



=== TEST 7: get value from gcp (failed to get google oauth token:identity authentication failed)
--- config
    location /t {
        content_by_lua_block {
            local conf = {
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
                    token_uri = "http://127.0.0.1:1980/google/secret/token",
                    scopes = "https://www.googleapis.com/auth/cloud",
                    entries_uri = "http://127.0.0.1:1980/google/secret/fail"
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
{"error":"identity authentication failed"}



=== TEST 8: get value from gcp (invalid response:no access to this scopes)
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
                    scopes = "https://www.googleapis.com/auth/cloud",
                    entries_uri = "http://127.0.0.1:1980/google/fail/"
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
failed to retrtive data from gcp secret manager: invalid status code



=== TEST 9: get value from gcp by auth_file(no find file)
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
failed to retrtive data from gcp secret manager: failed to read configuration, file: t/secret/conf/nofind.json



=== TEST 10: get value from gcp by auth_file(read success)
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



=== TEST 10: get value from gcp by auth_file(configuration is undefined)
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
failed to retrtive data from gcp secret manager: configuration is undefined, file: t/secret/conf/error.json
