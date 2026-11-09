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
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!defined $block->yaml_config) {
        $block->set_value("yaml_config", <<_EOC_);
apisix:
    proxy_mode: http&stream
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
_EOC_
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }

    my $extra_init_by_lua = <<_EOC_;
    local de = require("apisix.core").data_encryption
    local keyring = de.init_iv_tbl({"edd1c9f0985e76a2"})
    function _G.mark(v)
        return "\$ENC\$v1\$" .. assert(de.aes_cbc_encrypt(keyring, v))
    end
    function _G.stored(key)
        local res = assert(require("apisix.core").etcd.get(key))
        return res.body.node.value
    end
    function _G.admin(uri, method, body)
        local json = require("toolkit.json")
        local t = require("lib.test_admin").test
        local code, msg, res = t(uri, method, body and json.encode(body))
        if code >= 300 then
            return code, json.decode(msg)
        end
        return code, res and json.decode(res)
    end
_EOC_
    $block->set_value("extra_init_by_lua", $extra_init_by_lua);
});

run_tests;

__DATA__

=== TEST 1: encrypt_fields are stored marked, read back as plaintext
--- config
    location /t {
        content_by_lua_block {
            local code, body = admin("/apisix/admin/consumers", ngx.HTTP_PUT, {
                username = "foo",
                plugins = {["basic-auth"] = {username = "foo", password = "bar"}},
            })
            ngx.say(code)

            ngx.say(stored("/consumers/foo").plugins["basic-auth"].password)

            code, body = admin("/apisix/admin/consumers/foo", ngx.HTTP_GET)
            ngx.say(body.value.plugins["basic-auth"].password)

            code, body = admin("/apisix/admin/consumers", ngx.HTTP_GET)
            ngx.say(body.list[1].value.plugins["basic-auth"].password)
        }
    }
--- response_body
201
$ENC$v1$77+NmbYqNfN+oLm0aX5akg==
bar
bar



=== TEST 2: the data plane decrypts the marked value
--- config
    location /t {
        content_by_lua_block {
            local code = admin("/apisix/admin/routes/1", ngx.HTTP_PUT, {
                uri = "/hello",
                plugins = {["basic-auth"] = {}},
                upstream = {nodes = {["127.0.0.1:1980"] = 1}, type = "roundrobin"},
            })
            ngx.say(code)
        }
    }
--- response_body
201



=== TEST 3: hit the route
--- request
GET /hello
--- more_headers
Authorization: Basic Zm9vOmJhcg==
--- response_body
hello world



=== TEST 4: PATCH keeps a marked value encrypted exactly once
--- config
    location /t {
        content_by_lua_block {
            local code, body = admin("/apisix/admin/routes/1", ngx.HTTP_PUT, {
                uri = "/hello",
                plugins = {
                    ["limit-count"] = {
                        count = 2,
                        time_window = 60,
                        policy = "redis",
                        redis_host = "127.0.0.1",
                        redis_password = "secret",
                    },
                },
                upstream = {nodes = {["127.0.0.1:1980"] = 1}, type = "roundrobin"},
            })
            ngx.say(code)

            code = admin("/apisix/admin/routes/1", ngx.HTTP_PATCH, {desc = "patched"})
            ngx.say(code)
            ngx.say(stored("/routes/1").plugins["limit-count"].redis_password
                    == mark("secret"))

            code = admin("/apisix/admin/routes/1/plugins/limit-count/redis_password",
                         ngx.HTTP_PATCH, "new-secret")
            ngx.say(code)
            ngx.say(stored("/routes/1").plugins["limit-count"].redis_password
                    == mark("new-secret"))

            code, body = admin("/apisix/admin/routes/1", ngx.HTTP_GET)
            ngx.say(body.value.desc, " ", body.value.plugins["limit-count"].redis_password)
        }
    }
--- response_body
200
200
true
200
true
patched new-secret



=== TEST 5: plugin metadata is stored marked, read back as plaintext
--- config
    location /t {
        content_by_lua_block {
            local code, body = admin("/apisix/admin/plugin_metadata/azure-functions",
                                     ngx.HTTP_PUT, {master_apikey = "master-key"})
            ngx.say(code)
            ngx.say(stored("/plugin_metadata/azure-functions").master_apikey
                    == mark("master-key"))

            code, body = admin("/apisix/admin/plugin_metadata/azure-functions", ngx.HTTP_GET)
            ngx.say(body.value.master_apikey)

            code, body = admin("/apisix/admin/plugin_metadata", ngx.HTTP_GET)
            for _, item in ipairs(body.list) do
                if item.value.id == "azure-functions" then
                    ngx.say(item.value.master_apikey)
                end
            end
        }
    }
--- response_body
201
true
master-key
master-key



=== TEST 6: reads return marked values as stored, encryption off
--- yaml_config
apisix:
    proxy_mode: http&stream
    data_encryption:
        enable_encrypt_fields: false
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            assert(core.etcd.set("/routes/1", {
                id = "1",
                uri = "/hello",
                plugins = {
                    ["proxy-rewrite"] = {headers = {set = {["X-Secret"] = mark("hdr")}}},
                },
                upstream = {nodes = {["127.0.0.1:1980"] = 1}, type = "roundrobin"},
            }))
            assert(core.etcd.set("/stream_routes/1", {
                id = "1",
                plugins = {
                    ["limit-conn"] = {
                        conn = 1,
                        burst = 0,
                        default_conn_delay = 0.1,
                        key = "remote_addr",
                        policy = "redis",
                        redis_host = "127.0.0.1",
                        redis_password = mark("hdr"),
                    },
                },
                upstream = {nodes = {["127.0.0.1:1995"] = 1}, type = "roundrobin"},
            }))

            local code, body = admin("/apisix/admin/routes/1", ngx.HTTP_GET)
            ngx.say(body.value.plugins["proxy-rewrite"].headers.set["X-Secret"] == mark("hdr"))

            code, body = admin("/apisix/admin/routes", ngx.HTTP_GET)
            ngx.say(body.list[1].value.plugins["proxy-rewrite"].headers.set["X-Secret"]
                    == mark("hdr"))

            code, body = admin("/apisix/admin/stream_routes/1", ngx.HTTP_GET)
            ngx.say(body.value.plugins["limit-conn"].redis_password == mark("hdr"))

            assert(core.etcd.set("/plugin_metadata/azure-functions", {
                id = "azure-functions",
                master_apikey = mark("master-key"),
            }))
            code, body = admin("/apisix/admin/plugin_metadata/azure-functions", ngx.HTTP_GET)
            ngx.say(body.value.master_apikey == mark("master-key"))
            code, body = admin("/apisix/admin/plugin_metadata", ngx.HTTP_GET)
            for _, item in ipairs(body.list) do
                if item.value.id == "azure-functions" then
                    ngx.say(item.value.master_apikey == mark("master-key"))
                end
            end

            -- PATCH keeps the marked value it did not change encrypted at rest
            code = admin("/apisix/admin/routes/1", ngx.HTTP_PATCH, {desc = "patched"})
            ngx.say(code)
            ngx.say(stored("/routes/1").plugins["proxy-rewrite"].headers.set["X-Secret"]
                    == mark("hdr"))

            -- a value replaced by the PATCH is user input, stored as given
            code = admin("/apisix/admin/routes/1/plugins/proxy-rewrite/headers/set/X-Secret",
                         ngx.HTTP_PATCH, "new-hdr")
            ngx.say(code)
            ngx.say(stored("/routes/1").plugins["proxy-rewrite"].headers.set["X-Secret"])

            assert(core.etcd.delete("/stream_routes/1"))
        }
    }
--- response_body
true
true
true
true
true
200
true
200
new-hdr



=== TEST 7: a stored marked value that fails to decrypt
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            assert(core.etcd.set("/routes/1", {
                id = "1",
                uri = "/hello",
                plugins = {
                    ["proxy-rewrite"] = {headers = {set = {["X-Secret"] = "$ENC$v1$bad"}}},
                },
                upstream = {nodes = {["127.0.0.1:1980"] = 1}, type = "roundrobin"},
            }))

            -- reads return it as stored
            local code, body = admin("/apisix/admin/routes/1", ngx.HTTP_GET)
            ngx.say(code, " ", body.value.plugins["proxy-rewrite"].headers.set["X-Secret"])

            -- PATCH merges into it and keeps it as stored
            code, body = admin("/apisix/admin/routes/1", ngx.HTTP_PATCH, {desc = "patched"})
            ngx.say(code, " ", stored("/routes/1").plugins["proxy-rewrite"].headers.set["X-Secret"])

            assert(core.etcd.delete("/routes/1"))
        }
    }
--- response_body
200 $ENC$v1$bad
200 $ENC$v1$bad
--- error_log
failed to decrypt the value of plugin [proxy-rewrite] key [headers.set.X-Secret]



=== TEST 8: PATCH preserves marked fields outside encrypt_fields
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local original = mark("header-secret")
            assert(core.etcd.set("/routes/1", {
                id = "1",
                uri = "/hello",
                plugins = {
                    ["proxy-rewrite"] = {headers = {set = {["X-Secret"] = original}}},
                    ["limit-count"] = {
                        count = 2,
                        time_window = 60,
                        policy = "redis",
                        redis_host = "127.0.0.1",
                        redis_password = mark("redis-secret"),
                    },
                },
                upstream = {nodes = {["127.0.0.1:1980"] = 1}, type = "roundrobin"},
            }))

            local code = admin("/apisix/admin/routes/1", ngx.HTTP_PATCH, {desc = "patched"})
            ngx.say(code)
            local conf = stored("/routes/1")
            ngx.say(conf.desc)
            ngx.say(conf.plugins["proxy-rewrite"].headers.set["X-Secret"] == original)
            ngx.say(conf.plugins["limit-count"].redis_password == mark("redis-secret"))

            code = admin("/apisix/admin/routes/1/plugins/limit-count/redis_password",
                         ngx.HTTP_PATCH, "new-redis-secret")
            ngx.say(code)
            conf = stored("/routes/1")
            ngx.say(conf.plugins["proxy-rewrite"].headers.set["X-Secret"] == original)
            ngx.say(conf.plugins["limit-count"].redis_password == mark("new-redis-secret"))

            local body
            code, body = admin("/apisix/admin/routes/1", ngx.HTTP_GET)
            ngx.say(body.value.plugins["proxy-rewrite"].headers.set["X-Secret"])
            ngx.say(body.value.plugins["limit-count"].redis_password)

            -- An explicit replacement must not restore the previous ciphertext.
            code = admin("/apisix/admin/routes/1/plugins/proxy-rewrite/headers/set/X-Secret",
                         ngx.HTTP_PATCH, "replacement")
            ngx.say(code)
            ngx.say(stored("/routes/1").plugins["proxy-rewrite"].headers.set["X-Secret"])
        }
    }
--- response_body
200
patched
true
true
200
true
true
header-secret
new-redis-secret
200
replacement
