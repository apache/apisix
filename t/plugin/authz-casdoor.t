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

    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 10420;
        location /api/login/oauth/access_token {
            content_by_lua_block {
                local json_encode = require("toolkit.json").encode
                ngx.req.read_body()
                local arg = ngx.req.get_post_args()["code"]

                local core = require("apisix.core")
                local log = core.log

                if arg == "wrong" then
                    ngx.status = 200
                    ngx.say(json_encode({ access_token = "bbbbbbbbbb", expires_in = 0 }))
                    return
                end

                ngx.status = 200
                ngx.say(json_encode({ access_token = "aaaaaaaaaaaaaaaa", expires_in = 1000000 }))
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-casdoor")
            local fake_uri = "http://127.0.0.1:" .. ngx.var.server_port
            local callback_url = "http://127.0.0.1:" .. ngx.var.server_port ..
                                    "/anything/callback"
            local conf = {
                callback_url = callback_url,
                endpoint_addr = fake_uri,
                client_id = "7ceb9b7fda4a9061ec1c",
                client_secret = "3416238e1edf915eac08b8fe345b2b95cdba7e04"
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            local conf2 = {
                callback_url = callback_url .. "/?code=aaa",
                endpoint_addr = fake_uri,
                client_id = "7ceb9b7fda4a9061ec1c",
                client_secret = "3416238e1edf915eac08b8fe345b2b95cdba7e04"
            }
            ok, err = plugin.check_schema(conf2)
            if ok then
                ngx.say("err: shouldn't have passed sanity check")
            end

            local conf3 = {
                callback_url = callback_url,
                endpoint_addr = fake_uri .. "/",
                client_id = "7ceb9b7fda4a9061ec1c",
                client_secret = "3416238e1edf915eac08b8fe345b2b95cdba7e04"
            }
            ok, err = plugin.check_schema(conf3)
            if ok then
                ngx.say("err: shouldn't have passed sanity check")
            end

            ngx.say("done")

        }
    }
--- response_body
done
--- error_log
Using authz-casdoor endpoint_addr with no TLS is a security risk
Using authz-casdoor callback_url with no TLS is a security risk



=== TEST 2: using https should not give error
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-casdoor")
            local fake_uri = "https://127.0.0.1:" .. ngx.var.server_port
            local callback_url = "https://127.0.0.1:" .. ngx.var.server_port ..
                                    "/anything/callback"
            local conf = {
                callback_url = callback_url,
                endpoint_addr = fake_uri,
                client_id = "7ceb9b7fda4a9061ec1c",
                client_secret = "3416238e1edf915eac08b8fe345b2b95cdba7e04"
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")

        }
    }
--- response_body
done
--- no_error_log
Using authz-casdoor endpoint_addr with no TLS is a security risk
Using authz-casdoor callback_url with no TLS is a security risk



=== TEST 3: enable plugin test redirect
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-casdoor")
            local t = require("lib.test_admin").test

            local fake_uri = "http://127.0.0.1:10420"
            local callback_url = "http://127.0.0.1:" .. ngx.var.server_port ..
                                    "/anything/callback"
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "uri": "/anything/*",
                    "plugins": {
                        "authz-casdoor": {
                            "callback_url":"]] .. callback_url .. [[",
                            "endpoint_addr":"]] .. fake_uri .. [[",
                            "client_id":"7ceb9b7fda4a9061ec1c",
                            "client_secret":"3416238e1edf915eac08b8fe345b2b95cdba7e04"
                        },
                        "proxy-rewrite": {
                            "uri": "/echo"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "test.com:1980": 1
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.say("failed to set up routing rule")
            end
            ngx.say("done")

        }
    }
--- response_body
done



=== TEST 4: test redirect
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-casdoor")
            local t = require("lib.test_admin").test

            local code, body = t('/anything/d?param1=foo&param2=bar', ngx.HTTP_GET, [[]])
            if code ~= 302 then
                ngx.say("should have redirected")
            end

            ngx.say("done")

        }
    }
--- response_body
done



=== TEST 5: enable fake casdoor
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                        "uri": "/api/login/oauth/access_token",
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
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



=== TEST 6: test fake casdoor
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-casdoor")
            local t = require("lib.test_admin").test
            local httpc = require("resty.http").new()
            local cjson = require("cjson")
            local fake_uri = "http://127.0.0.1:10420/api/login/oauth/access_token"

            local res, err = httpc:request_uri(fake_uri, {method = "GET"})
            if not res then
                ngx.say(err)
            end
            local data = cjson.decode(res.body)
            if not data then
                ngx.say("invalid res.body")
            end
            if not data.access_token == "aaaaaaaaaaaaaaaa" then
                ngx.say("invalid token")
            end
            ngx.say("done")

        }
    }
--- response_body
done



=== TEST 7: test code handling
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-casdoor")
            local core = require("apisix.core")
            local log = core.log
            local t = require("lib.test_admin").test
            local cjson = require("cjson")
            local fake_uri = "http://127.0.0.1:" .. ngx.var.server_port ..
                                "/anything/d?param1=foo&param2=bar"
            local callback_url = "http://127.0.0.1:" .. ngx.var.server_port ..
                                    "/anything/callback?code=aaa&state="

            local httpc = require("resty.http").new()
            local res1, err1 = httpc:request_uri(fake_uri, {method = "GET"})
            if not res1 then
                ngx.say(err1)
            end

            local cookie = res1.headers["Set-Cookie"]
            local re_url = res1.headers["Location"]
            local m, err = ngx.re.match(re_url, "state=([0-9]*)")
            if err or not m then
                log.error(err)
                ngx.exit()
            end
            local state = m[1]

            local res2, err2 = httpc:request_uri(callback_url..state, {
                method = "GET",
                headers = {Cookie = cookie}
            })
            if not res2 then
                ngx.say(err2)
            end
            if res2.status ~= 302 then
                log.error(res2.status)
            end

            local cookie2 = res2.headers["Set-Cookie"]
            local res3, err3 = httpc:request_uri(fake_uri, {
                method = "GET",
                headers = {Cookie = cookie2}

            })
            if not res3 then
                ngx.say(err3)
            end
            if res3.status >= 300 then
                log.error(res3.status,res3.headers["Location"])
            end
            ngx.say("done")

        }
    }
--- response_body
done



=== TEST 8: incorrect test code handling
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-casdoor")
            local t = require("lib.test_admin").test
            local cjson = require("cjson")

            local callback_url = "http://127.0.0.1:" .. ngx.var.server_port ..
                                    "/anything/callback?code=aaa&state=bbb"

            local httpc = require("resty.http").new()
            local res1, err1 = httpc:request_uri(callback_url, {method = "GET"})
            if res1.status ~= 503 then
                ngx.say(res1.status)
            end
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
no session found



=== TEST 9: incorrect state handling
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-casdoor")
            local core = require("apisix.core")
            local log = core.log
            local t = require("lib.test_admin").test
            local cjson = require("cjson")
            local fake_uri = "http://127.0.0.1:" .. ngx.var.server_port ..
                                "/anything/d?param1=foo&param2=bar"
            local callback_url = "http://127.0.0.1:" .. ngx.var.server_port ..
                                    "/anything/callback?code=aaa&state="

            local httpc = require("resty.http").new()
            local res1, err1 = httpc:request_uri(fake_uri, {method = "GET"})
            if not res1 then
                ngx.say(err1)
            end

            local cookie = res1.headers["Set-Cookie"]
            local re_url = res1.headers["Location"]
            local m, err = ngx.re.match(re_url, "state=([0-9]*)")
            if err or not m then
                log.error(err)
            end
            local state = m[1]+10

            local res2, err2 = httpc:request_uri(callback_url..state, {
                method = "GET",
                headers = {Cookie = cookie}
            })
            if not res2 then
                ngx.say(err2)
            end
            if res2.status ~= 302 then
                log.error(res2.status)
            end

            local cookie2 = res2.headers["Set-Cookie"]
            local res3, err3 = httpc:request_uri(fake_uri, {
                method = "GET",
                headers = {Cookie = cookie2}
            })
            if not res3 then
                ngx.say(err3)
            end
            if res3.status ~= 503 then
                log.error(res3.status)
            end
            ngx.say("done")

        }
    }
--- response_body
done
--- error_log
invalid state



=== TEST 10: test incorrect access_token
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-casdoor")
            local core = require("apisix.core")
            local log = core.log
            local t = require("lib.test_admin").test
            local cjson = require("cjson")
            local fake_uri = "http://127.0.0.1:" .. ngx.var.server_port ..
                                "/anything/d?param1=foo&param2=bar"
            local callback_url = "http://127.0.0.1:" .. ngx.var.server_port ..
                                    "/anything/callback?code=wrong&state="

            local httpc = require("resty.http").new()
            local res1, err1 = httpc:request_uri(fake_uri, {method = "GET"})
            if not res1 then
                ngx.say(err1)
            end

            local cookie = res1.headers["Set-Cookie"]
            local re_url = res1.headers["Location"]
            local m, err = ngx.re.match(re_url, "state=([0-9]*)")
            if err or not m then
                log.error(err)
                ngx.exit()
            end
            local state = m[1]

            local res2, err2 = httpc:request_uri(callback_url..state, {
                method = "GET",
                headers = {Cookie = cookie}
            })
            if not res2 then
                ngx.say(err2)
            end
            if res2.status ~= 302 then
                log.error(res2.status)
            end

            local cookie2 = res2.headers["Set-Cookie"]
            local res3, err3 = httpc:request_uri(fake_uri, {
                method = "GET",
                headers = {Cookie = cookie2}

            })
            if not res3 then
                ngx.say(err3)
            end
            if res3.status ~= 503 then
                log.error(res3.status)
            end
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
failed when accessing token: invalid access_token



=== TEST 11: data encryption for client_secret
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local callback_url = "http://127.0.0.1:" .. ngx.var.server_port ..
                                 "/anything/callback"
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "uri": "/anything/*",
                    "plugins": {
                        "authz-casdoor": {
                            "callback_url":"]] .. callback_url .. [[",
                            "endpoint_addr": "http://127.0.0.1:10420",
                            "client_id":"7ceb9b7fda4a9061ec1c",
                            "client_secret":"3416238e1edf915eac08b8fe345b2b95cdba7e04"
                        },
                        "proxy-rewrite": {
                            "uri": "/echo"
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "test.com:1980": 1
                        }
                    }
                }]]
            )

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

            ngx.say(res.value.plugins["authz-casdoor"].client_secret)

            -- get plugin conf from etcd, password is encrypted
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/routes/1'))
            ngx.say(res.body.node.value.plugins["authz-casdoor"].client_secret)
        }
    }
--- response_body
3416238e1edf915eac08b8fe345b2b95cdba7e04
YUfqAO0kPXjZIoAbPSuryCkUDksEmwSq08UDTIUWolN6KQwEUrh72TazePueo4/S
