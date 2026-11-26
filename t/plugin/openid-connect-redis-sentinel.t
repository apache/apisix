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
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }

    # mock OpenID provider and upstream used by the end-to-end tests
    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 11980;
        server_name localhost;

        location / {
            content_by_lua_block {
                ngx.say("hello from upstream")
            }
        }
    }
    server {
        listen 16969;
        server_name localhost;

        location /.well-known/openid-configuration {
            content_by_lua_block {
                ngx.header.content_type = "application/json"
                ngx.say([[
                {
                    "issuer": "http://127.0.0.1:16969",
                    "authorization_endpoint": "http://127.0.0.1:16969/authorize",
                    "token_endpoint": "http://127.0.0.1:16969/token",
                    "userinfo_endpoint": "http://127.0.0.1:16969/userinfo",
                    "jwks_uri": "http://127.0.0.1:16969/jwks"
                }
                ]])
            }
        }

        location /token {
            content_by_lua_block {
                local jwt = require("resty.jwt")
                local cjson = require("cjson")

                ngx.header.content_type = "application/json"
                local id_token = jwt:sign("test_secret", {
                    header = {typ = "JWT", alg = "HS256"},
                    payload = {
                        sub = "user_123",
                        iss = "http://127.0.0.1:16969",
                        aud = "test_client",
                        exp = ngx.time() + 3600,
                        iat = ngx.time(),
                    },
                })
                ngx.say(cjson.encode({
                    access_token = "access_token_1",
                    expires_in = 3600,
                    refresh_token = "refresh_token_1",
                    id_token = id_token,
                    token_type = "Bearer",
                }))
            }
        }

        location /userinfo {
            content_by_lua_block {
                ngx.header.content_type = "application/json"
                ngx.say([[{"sub": "user_123"}]])
            }
        }

        location /jwks {
            content_by_lua_block {
                ngx.header.content_type = "application/json"
                ngx.say([[{"keys": []}]])
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: check schema with valid redis sentinel session configuration
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "c",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                    storage = "redis",
                    redis = {
                        sentinels = {
                            {host = "127.0.0.1", port = 26379},
                            {host = "127.0.0.1", port = 26380},
                        },
                        master = "mymaster",
                        sentinel_username = "admin",
                        sentinel_password = "admin-password",
                        username = "master",
                        password = "master-password",
                        prefix = "sessions",
                    }
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
done



=== TEST 2: sentinels require master
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "c",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                    storage = "redis",
                    redis = {
                        sentinels = {
                            {host = "127.0.0.1", port = 26379},
                        },
                    }
                }
            })
            ngx.say(ok and "done" or err)
        }
    }
--- response_body_like
property "master" is required when "sentinels" is set



=== TEST 3: master requires sentinels
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "c",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                    storage = "redis",
                    redis = {
                        master = "mymaster",
                    }
                }
            })
            ngx.say(ok and "done" or err)
        }
    }
--- response_body_like
property "sentinels" is required when "master" is set



=== TEST 4: sentinels must not be empty
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "c",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                    storage = "redis",
                    redis = {
                        sentinels = {},
                        master = "mymaster",
                    }
                }
            })
            ngx.say(ok and "done" or err)
        }
    }
--- response_body_like
property "sentinels" validation failed: expect array to have at least 1 items



=== TEST 5: sentinel node requires port
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "c",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                    storage = "redis",
                    redis = {
                        sentinels = {
                            {host = "127.0.0.1"},
                        },
                        master = "mymaster",
                    }
                }
            })
            ngx.say(ok and "done" or err)
        }
    }
--- response_body_like
property "port" is required



=== TEST 6: sentinel credentials require sentinels
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "c",
                session = {
                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                    storage = "redis",
                    redis = {
                        sentinel_password = "admin-password",
                    }
                }
            })
            ngx.say(ok and "done" or err)
        }
    }
--- response_body_like
property "sentinels" is required when "sentinel_password" is set



=== TEST 7: data encryption for session.redis.sentinel_password
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
            local sentinel_password = "super-secret-sentinel-password"
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 json.encode({
                     plugins = {
                         ["openid-connect"] = {
                             client_id = "test_client",
                             client_secret = "test_secret",
                             discovery = "http://127.0.0.1:16969/.well-known/openid-configuration",
                             redirect_uri = "http://127.0.0.1/api/sentinel/callback",
                             session = {
                                 secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                                 storage = "redis",
                                 redis = {
                                     sentinels = {
                                         {host = "127.0.0.1", port = 26380},
                                     },
                                     master = "mymaster",
                                     sentinel_username = "admin",
                                     sentinel_password = sentinel_password,
                                 }
                             }
                         }
                     },
                     upstream = {
                         nodes = {
                             ["127.0.0.1:11980"] = 1
                         },
                         type = "roundrobin"
                     },
                     uri = "/api/sentinel*"
                 })
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

            local redis_conf = res.value.plugins["openid-connect"].session.redis
            ngx.say(redis_conf.sentinel_password == sentinel_password)

            -- get plugin conf from etcd, password must be encrypted (not plaintext)
            local etcd = require("apisix.core.etcd")
            local etcd_res = assert(etcd.get('/routes/1'))
            local stored = etcd_res.body.node.value.plugins["openid-connect"]
                                   .session.redis.sentinel_password
            ngx.say(type(stored) == "string" and stored ~= "" and stored ~= sentinel_password)
        }
    }
--- response_body
true
true
--- no_error_log
[alert]



=== TEST 8: authorization code flow stores the session through redis sentinel
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local redis = require("resty.redis")

            local cases = {
                {
                    name = "sentinel without auth",
                    prefix = "oidc_sentinel_anon",
                    redis = {
                        sentinels = {
                            {host = "127.0.0.1", port = 26379},
                        },
                        master = "mymaster",
                    },
                },
                {
                    name = "sentinel with auth",
                    prefix = "oidc_sentinel_auth",
                    redis = {
                        sentinels = {
                            {host = "127.0.0.1", port = 26380},
                        },
                        master = "mymaster",
                        sentinel_username = "admin",
                        sentinel_password = "admin-password",
                        username = "master",
                        password = "master-password",
                    },
                },
            }

            local function get_cookie(headers, name)
                local cookies = headers["Set-Cookie"]
                if not cookies then
                    return nil
                end
                if type(cookies) == "string" then
                    cookies = {cookies}
                end
                for _, c in ipairs(cookies) do
                    local val = string.match(c, name .. "=([^;]+)")
                    if val then
                        return name .. "=" .. val
                    end
                end
                return nil
            end

            local base = "http://127.0.0.1:" .. ngx.var.server_port
            local discovery = "http://127.0.0.1:16969/.well-known/openid-configuration"

            for _, case in ipairs(cases) do
                case.redis.prefix = case.prefix
                local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    json.encode({
                        plugins = {
                            ["openid-connect"] = {
                                client_id = "test_client",
                                client_secret = "test_secret",
                                discovery = discovery,
                                redirect_uri = "http://127.0.0.1/api/sentinel/callback",
                                session = {
                                    secret = "jwcE5v3pM9VhqLxmxFOH9uZaLo8u7KQK",
                                    storage = "redis",
                                    redis = case.redis,
                                },
                            },
                        },
                        upstream = {
                            nodes = {
                                ["127.0.0.1:11980"] = 1
                            },
                            type = "roundrobin"
                        },
                        uri = "/api/sentinel*"
                    })
                )
                if code >= 300 then
                    ngx.say(case.name, ": failed to set route: ", body)
                    return
                end
                ngx.sleep(0.5)

                local httpc = http.new()

                -- 1. unauthenticated request starts the authorization code flow
                local res, err = httpc:request_uri(base .. "/api/sentinel/start")
                if not res or res.status ~= 302 then
                    ngx.say(case.name, ": failed to start flow: ", res and res.status or err)
                    return
                end
                local initial_cookie = get_cookie(res.headers, "session")
                local state = string.match(res.headers["Location"] or "", "state=([^&]+)")
                if not initial_cookie or not state then
                    ngx.say(case.name, ": missing session cookie or state")
                    return
                end

                -- 2. the OP redirects back with a code and the same state
                res, err = httpc:request_uri(
                    base .. "/api/sentinel/callback?code=mock_code&state=" .. state,
                    {headers = {["Cookie"] = initial_cookie}}
                )
                if not res then
                    ngx.say(case.name, ": callback failed: ", err)
                    return
                end
                local auth_cookie = get_cookie(res.headers, "session")
                if not auth_cookie then
                    ngx.say(case.name, ": no authenticated session cookie, status: ",
                            res.status)
                    return
                end

                -- 3. the session is restored from redis and the request is proxied
                res, err = httpc:request_uri(base .. "/api/sentinel/resource",
                    {headers = {["Cookie"] = auth_cookie}})
                if not res or res.status ~= 200 then
                    ngx.say(case.name, ": authenticated request failed: ",
                            res and res.status or err)
                    return
                end

                -- 4. the session data lives in the master discovered via sentinel
                local red = redis:new()
                red:set_timeout(1000)
                local ok, cerr = red:connect("127.0.0.1", 6479)
                if not ok then
                    ngx.say(case.name, ": failed to connect to redis master: ", cerr)
                    return
                end
                local keys = red:keys(case.prefix .. ":*")
                red:close()
                if type(keys) ~= "table" or #keys == 0 then
                    ngx.say(case.name, ": no session stored in redis master")
                    return
                end

                ngx.say(case.name, ": passed")
            end
        }
    }
--- response_body
sentinel without auth: passed
sentinel with auth: passed
