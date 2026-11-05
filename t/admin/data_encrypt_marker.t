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
        write_marker: true
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

=== TEST 1: write_marker: encrypt_fields are stored marked, read back as plaintext
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



=== TEST 4: write_marker: PATCH keeps a marked value encrypted exactly once
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



=== TEST 5: write_marker: plugin metadata is stored marked, read back as plaintext
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



=== TEST 6: write_marker off: encrypt_fields are stored without the marker
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
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
        }
    }
--- response_body
200
77+NmbYqNfN+oLm0aX5akg==
bar



=== TEST 7: write_marker has no effect without enable_encrypt_fields
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: false
        write_marker: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local code = admin("/apisix/admin/consumers", ngx.HTTP_PUT, {
                username = "foo",
                plugins = {["basic-auth"] = {username = "foo", password = "bar"}},
            })
            ngx.say(code)
            ngx.say(stored("/consumers/foo").plugins["basic-auth"].password)
        }
    }
--- response_body
200
bar



=== TEST 8: reads return plaintext for marked values outside encrypt_fields, encryption off
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
                plugins = {["ip-restriction"] = {whitelist = {mark("127.0.0.1")}}},
                upstream = {nodes = {["127.0.0.1:1995"] = 1}, type = "roundrobin"},
            }))

            local code, body = admin("/apisix/admin/routes/1", ngx.HTTP_GET)
            ngx.say(body.value.plugins["proxy-rewrite"].headers.set["X-Secret"])

            code, body = admin("/apisix/admin/routes", ngx.HTTP_GET)
            ngx.say(body.list[1].value.plugins["proxy-rewrite"].headers.set["X-Secret"])

            code, body = admin("/apisix/admin/stream_routes/1", ngx.HTTP_GET)
            ngx.say(body.value.plugins["ip-restriction"].whitelist[1])

            -- PATCH merges the decrypted value; with encryption off it is stored as is
            code = admin("/apisix/admin/routes/1", ngx.HTTP_PATCH, {desc = "patched"})
            ngx.say(code)
            ngx.say(stored("/routes/1").plugins["proxy-rewrite"].headers.set["X-Secret"])

            assert(core.etcd.delete("/stream_routes/1"))
        }
    }
--- response_body
hdr
hdr
127.0.0.1
200
hdr



=== TEST 9: a stored marked value that fails to decrypt
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

            -- PATCH refuses to merge into it
            code, body = admin("/apisix/admin/routes/1", ngx.HTTP_PATCH, {desc = "patched"})
            ngx.say(code, " ", body.error_msg)

            assert(core.etcd.delete("/routes/1"))
        }
    }
--- response_body
200 $ENC$v1$bad
400 failed to decrypt the stored configuration: failed to decrypt the value of plugin [proxy-rewrite] key [headers.set.X-Secret]: decrypt failed
--- error_log
failed to decrypt the routes in the response



=== TEST 10: reject user input starting with the reserved prefix
--- config
    location /t {
        content_by_lua_block {
            local upstream = {nodes = {["127.0.0.1:1980"] = 1}, type = "roundrobin"}
            local function route(v)
                return {
                    uri = "/hello",
                    plugins = {["proxy-rewrite"] = {headers = {set = {["X-A"] = v}}}},
                    upstream = upstream,
                }
            end

            local cases = {
                {"/apisix/admin/routes/1", ngx.HTTP_PUT, route("$ENC$v1$abc")},
                {"/apisix/admin/routes/1", ngx.HTTP_PUT, route("$ENC$v2$abc")},
                {"/apisix/admin/routes", ngx.HTTP_POST, route("$ENC$")},
                {"/apisix/admin/services/1", ngx.HTTP_PUT, {
                    plugins = {["proxy-rewrite"] = {uri = "$ENC$x"}},
                }},
                {"/apisix/admin/global_rules/1", ngx.HTTP_PUT, {
                    plugins = {["ip-restriction"] = {whitelist = {"127.0.0.1", "$ENC$x"}}},
                }},
                {"/apisix/admin/consumers", ngx.HTTP_PUT, {
                    username = "jack",
                    plugins = {["key-auth"] = {key = "$ENC$v1$abc"}},
                }},
                {"/apisix/admin/consumers/foo/credentials/c1", ngx.HTTP_PUT, {
                    plugins = {["key-auth"] = {key = "$ENC$v1$abc"}},
                }},
                {"/apisix/admin/plugin_metadata/azure-functions", ngx.HTTP_PUT, {
                    master_apikey = "$ENC$v1$abc",
                }},
                {"/apisix/admin/stream_routes/1", ngx.HTTP_PUT, {
                    plugins = {["ip-restriction"] = {whitelist = {"$ENC$v1$abc"}}},
                    upstream = upstream,
                }},
                {"/apisix/admin/routes/1", ngx.HTTP_PATCH, {
                    plugins = {["proxy-rewrite"] = {uri = "$ENC$x"}},
                }},
                {"/apisix/admin/routes/1/plugins/proxy-rewrite", ngx.HTTP_PATCH, {
                    uri = "$ENC$x",
                }},
                {"/apisix/admin/routes/1/plugins/proxy-rewrite/uri", ngx.HTTP_PATCH, "$ENC$x"},
            }
            for _, c in ipairs(cases) do
                local code, body = admin(c[1], c[2], c[3])
                ngx.say(code, " ", body.error_msg)
            end
        }
    }
--- response_body
400 invalid value of plugins.proxy-rewrite.headers.set.X-A: the prefix "$ENC$" is reserved for encrypted values
400 invalid value of plugins.proxy-rewrite.headers.set.X-A: the prefix "$ENC$" is reserved for encrypted values
400 invalid value of plugins.proxy-rewrite.headers.set.X-A: the prefix "$ENC$" is reserved for encrypted values
400 invalid value of plugins.proxy-rewrite.uri: the prefix "$ENC$" is reserved for encrypted values
400 invalid value of plugins.ip-restriction.whitelist.2: the prefix "$ENC$" is reserved for encrypted values
400 invalid value of plugins.key-auth.key: the prefix "$ENC$" is reserved for encrypted values
400 invalid value of plugins.key-auth.key: the prefix "$ENC$" is reserved for encrypted values
400 invalid value of master_apikey: the prefix "$ENC$" is reserved for encrypted values
400 invalid value of plugins.ip-restriction.whitelist.1: the prefix "$ENC$" is reserved for encrypted values
400 invalid value of plugins.proxy-rewrite.uri: the prefix "$ENC$" is reserved for encrypted values
400 invalid value of plugins.proxy-rewrite.uri: the prefix "$ENC$" is reserved for encrypted values
400 invalid value of plugins.proxy-rewrite.uri: the prefix "$ENC$" is reserved for encrypted values



=== TEST 11: reject the reserved prefix without write_marker, accept it elsewhere
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: false
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local upstream = {nodes = {["127.0.0.1:1980"] = 1}, type = "roundrobin"}

            local code, body = admin("/apisix/admin/routes/1", ngx.HTTP_PUT, {
                uri = "/hello",
                plugins = {["proxy-rewrite"] = {uri = "$ENC$v1$abc"}},
                upstream = upstream,
            })
            ngx.say(code, " ", body.error_msg)

            -- not a prefix
            code = admin("/apisix/admin/routes/1", ngx.HTTP_PUT, {
                uri = "/hello",
                plugins = {["proxy-rewrite"] = {uri = "/a$ENC$"}},
                upstream = upstream,
            })
            ngx.say(code)

            -- outside the plugin confs
            code = admin("/apisix/admin/routes/1", ngx.HTTP_PATCH, {desc = "$ENC$desc"})
            ngx.say(code)

            -- a stored value is not user input
            assert(core.etcd.set("/routes/1", {
                id = "1",
                uri = "/hello",
                plugins = {
                    ["proxy-rewrite"] = {headers = {set = {["X-A"] = "$ENC$v2$stored"}}},
                },
                upstream = upstream,
            }))
            code = admin("/apisix/admin/routes/1", ngx.HTTP_PATCH, {desc = "patched"})
            ngx.say(code, " ", stored("/routes/1").plugins["proxy-rewrite"].headers.set["X-A"])
        }
    }
--- response_body
400 invalid value of plugins.proxy-rewrite.uri: the prefix "$ENC$" is reserved for encrypted values
201
200
200 $ENC$v2$stored
