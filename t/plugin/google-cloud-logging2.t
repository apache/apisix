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

=== TEST 1: set route (verify batch queue default params)
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



=== TEST 2: data encryption for auth_config.private_key
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - qeddd145sfvddff3
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
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
            ngx.sleep(0.1)

            -- get plugin conf from admin api, password is decrypted
            local code, message, res = t('/apisix/admin/routes/1',
                ngx.HTTP_GET
            )
            res = json.decode(res)
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            ngx.say(res.value.plugins["google-cloud-logging"].auth_config.private_key)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/1'))
            ngx.say(res.body.node.value.plugins["google-cloud-logging"].auth_config.private_key)
        }
    }
--- response_body
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
-----END PRIVATE KEY-----
YnwwDKc5vNzo0OU4StTRQbwgCnTZ3dmYiBFm8aGnvTxlE86D2nT07Q3BWhUdky6OGIox4MRLbiHz13NZjyUao/Nudh4PeTj5wMldPD5YvNWtbTG4ig/TNSdBncmIQPLPaUqSweE61pnASxodpTlBJ5k9yxfTmwBTOkzZevoKy9D2E4wF9vGCdkcPK/tAkvRoJTj6xD3xVuAbkcap/81oHplUZZ+ghlEnBZgOH8UMa73UfeNbOQVHD2mlU0LxkTXtwFhHWl50adrt890VDHev0+FUUDjv5Ysl8r/nnnlyq3SV4oqJfs/IVRKROe93e8sJ2/49o7kEv2XT1/6DjM/VsSLKfAi5rLNobcSaSzztSSLkrBFKQvvy2rRA7GFWKbIk+rPZhYmTMItDJv23XP6uzaLRPoq2f/AnRTKpWmA8Dk9TfFHsZLupKi1bmjCdtK8lpMCf9Au1rezt7+2BybQrtbbDbwPzC5bKHmKhc0GPTUzLAWQBin3tuZxSfk/MqRtG+AemwnFTHivJrfRwmc3db+b9W6WX09mV488f2M4qbqBmkiFU5VARWCGZ5vbop2KGhmB2fQPXTmj8QSYk6fBxFDnfzTfnYMIu2cQsbSBPCnoPinQNpBfFD3RQkkCiNtJ8GA8DWsivWsnW4jWyPmkIN/P1eLW1DSsU6V4cbhTQJs6/LzOCGAZB/ewu3mr1SDLWJPlIWW6atC/g0uiXkZ3VLUsS0BQffITf8sVXyz/BEbflLlT777zERDKyz/qS2JyR6U8s2h3Yg+GncPUCEF6Lx5Veb1lL+zs+Stvv+5/t2GfDlNYiwTU8HeffhEGgAv1s86OPo3CfWe7lEnu/MFHIm0czVenYdEVy449xj66DHqXUQVzVc+3NelW15FrKhcvU0Cxwqfk+xEOE185ssD06L+tOGjxPPvADjlcQQ1crH+tEcTTLnZZ/e16I10kcc5rBJwDy4COoeY6DZ0dFwtAdbjoR/KaSTGLK6n/u9Ow7OGDPZog4LhrzMOn2T7hk/oaMOKhlDvKroiSijhhkrQf5ZDhhh3GQn/ZRXjyiPWBqKEQiBJGyZ/iRONzJLsF8U8vsBzBToxmTe9prlwHusgAEIBUFrZRSvsVgsPCFOyJ6XJXDTdcCInHUGI9LsxWdlojYvvNuSvavkw1I4K+VBmlEG5FCMx56eX2X49hfXwRcM1ZyRRrmq6cRh+33aMeMLAtpKgTsQgmB/I01mGNZlstvU0XEFnCPuWcks50BTnvPEbU7GZJLE3HFmGb3vyC57E8oTR2FjhDrevPlLkxMPrLvXhwbmV+3YiZYq+8k6oBKfrrq41JRKr+SJDb7m6xL8AuZccMrNhDrkByQLi6zn95dIYc3+vNU4XBzvhpb7HMj2wvorxEW2HpQ+OVSZiZSCU6m4Fx6juj1D5pGs1nr68ybihqMrXuZBKP4b9Y6sw99kNmnWBdwNiY95sWy1qUe0MJq3r44hhVHvCUmzOVyO4aBmhMwgkaSQWpEeQwyIWENM1IMU6WUrKCSuLuKJAl5bM++ThBaLvIIMCyXl39136jHp97aVmHRXbSMPcSAb8l/YQ6SLK0HBxmFTXvroxHmPxPqrJ5jz65C72+uArgOZxJN6tyimIcTMyoJoN7N+QKxDLjgmqnJyEcthycEK3gikyloWsLppzEmHLHBDXlKpJLflvUujYrNsKf2xohx31gIlxBWCHP/1KL3QAehn+FEWUWsXn2hWAR0KAtmIOM7gZuCY8yKNDfXrAZJs14rwDlTbnhJvyijt1Tr6gleehmJDKSm2vM/NbznVTKwJDyMRner+vvc4zD06az/Y6Y4oM0e0IWM2fMaiiwjNAaKhhwJzqvM1c8+ZOfuRajmHFECEkYgXCKZiQxQihFG2wWp2i+xEGGwP2e+FbDdY9Ygyvw5SUvahyoX36AYbbTBOFY6E9aYUIM/Et8ZuXoWs1QaxGfJwcVvueqke45y3GKkp54sHXhrqfKX0TTiw6DCUs6dRTybxOjmjJCKp6Yw4KGWY0t3J0xbK08KTUMeHNxgtfYcz1/Wg/Q61CkUJkRNBninAAkEz8rV2olBHy1GZFFjCQySAyPH4PtWm1S4sBzdsui5wT+m2pC/DsCcQW++TGH9LdaHeT8B9u32lYToVN1/L2j5kjkhN13sNKfb6I9yYTnUqweQFU79toBfDt+6KNNfIA1TcmvZw8RcuMOArEqJQ6OPOhgUQBwsZaGeqFmAE4q64n5raS4OCdWtasFtItW3c5QHxkKoEEER04glVsCoxOvc80U=



=== TEST 3: set route to test custom log format
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

            local code, body = t('/apisix/admin/plugin_metadata/google-cloud-logging',
                 ngx.HTTP_PUT,
                 [[{
                        "log_format": {
                            "host": "$host",
                            "@timestamp": "$time_iso8601",
                            "client_ip": "$remote_addr"
                        }
                }]]
                )
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



=== TEST 4: hit
--- extra_init_by_lua
    local decode = require("toolkit.json").decode
    local up = require("lib.server")
    up.google_logging_entries = function()
        ngx.log(ngx.WARN, "the mock backend is hit")

        ngx.req.read_body()
        local data = ngx.req.get_body_data()
        data = decode(data)
        assert(data.entries[1].jsonPayload.client_ip == "127.0.0.1")
        assert(data.entries[1].resource.type == "global")
        ngx.say('{}')
    end
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- error_log
the mock backend is hit
--- no_error_log
[error]



=== TEST 5: bad custom log format
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/google-cloud-logging',
                 ngx.HTTP_PUT,
                 [[{
                        "log_format": "'$host' '$time_iso8601'"
                 }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"log_format\" validation failed: wrong type: expected object, got string"}



=== TEST 6: set route to test custom log format in route
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
                        log_format = {
                            host = "$host",
                            ["@timestamp"] = "$time_iso8601",
                            vip = "$remote_addr"
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



=== TEST 7: hit
--- extra_init_by_lua
    local decode = require("toolkit.json").decode
    local up = require("lib.server")
    up.google_logging_entries = function()
        ngx.log(ngx.WARN, "the mock backend is hit")

        ngx.req.read_body()
        local data = ngx.req.get_body_data()
        data = decode(data)
        assert(data.entries[1].jsonPayload.vip == "127.0.0.1")
        assert(data.entries[1].resource.type == "global")
        ngx.say('{}')
    end
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- error_log
the mock backend is hit
--- no_error_log
[error]
