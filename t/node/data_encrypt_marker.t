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

    if (!defined $block->request && !defined $block->stream_request) {
        $block->set_value("request", "GET /t");
    }

    if (!defined $block->yaml_config) {
        $block->set_value("yaml_config", <<_EOC_);
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
_EOC_
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }

    # write the resources straight to etcd, the way the control plane does
    my $extra_init_by_lua = <<_EOC_;
    local de = require("apisix.core").data_encryption
    local keyring = de.init_iv_tbl({"edd1c9f0985e76a2"})
    function _G.enc(v)
        return assert(de.aes_cbc_encrypt(keyring, v))
    end
    function _G.mark(v)
        return "\$ENC\$v1\$" .. enc(v)
    end
    function _G.get(path, headers)
        local http = require("resty.http")
        local res = assert(http.new():request_uri("http://127.0.0.1:" .. ngx.var.server_port
                                                  .. path, {headers = headers}))
        return res
    end
    function _G.del(key)
        assert(require("apisix.core").etcd.delete(key))
    end
    function _G.put(key, value)
        local res, err = require("apisix.core").etcd.set(key, value)
        if not res then
            ngx.say(err)
            return
        end
    end
_EOC_
    $block->set_value("extra_init_by_lua", $extra_init_by_lua);
});

run_tests;

__DATA__

=== TEST 1: route: decrypt a marked value of a field outside encrypt_fields
--- config
    location /t {
        content_by_lua_block {
            put("/routes/1", {
                uri = "/uri",
                plugins = {
                    ["proxy-rewrite"] = {
                        headers = {
                            set = {["X-Secret"] = mark("route-secret")},
                        },
                    },
                },
                upstream = {nodes = {["127.0.0.1:1980"] = 1}, type = "roundrobin"},
            })
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: hit the route
--- request
GET /uri
--- response_body
uri: /uri
host: localhost
x-real-ip: 127.0.0.1
x-secret: route-secret



=== TEST 3: marked value that fails to decrypt makes the route invalid
--- config
    location /t {
        content_by_lua_block {
            put("/routes/2", {
                uri = "/hello",
                plugins = {
                    ["response-rewrite"] = {
                        headers = {
                            set = {["X-Other"] = mark("other-secret")},
                        },
                    },
                    ["proxy-rewrite"] = {
                        headers = {
                            set = {["X-Secret"] = "$ENC$v1$" .. enc("x"):sub(2)},
                        },
                    },
                },
                upstream = {nodes = {["127.0.0.1:1980"] = 1}, type = "roundrobin"},
            })
            ngx.sleep(0.5)
            ngx.say(get("/hello").status)
            del("/routes/2")
        }
    }
--- response_body
404
--- error_log
failed to decrypt the value of plugin [proxy-rewrite] key [headers.set.X-Secret]
--- no_error_log
other-secret



=== TEST 4: marked value is decrypted even when enable_encrypt_fields is off
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: false
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            put("/routes/1", {
                uri = "/uri",
                plugins = {
                    ["proxy-rewrite"] = {
                        headers = {
                            set = {["X-Secret"] = mark("route-secret")},
                        },
                    },
                },
                upstream = {nodes = {["127.0.0.1:1980"] = 1}, type = "roundrobin"},
            })
            ngx.sleep(0.5)
            ngx.say(get("/uri").body:match("x%-secret: [^\n]*"))
        }
    }
--- response_body
x-secret: route-secret



=== TEST 5: service and global rule: decrypt marked values
--- config
    location /t {
        content_by_lua_block {
            put("/services/1", {
                plugins = {
                    ["proxy-rewrite"] = {
                        headers = {
                            set = {["X-Service-Secret"] = mark("service-secret")},
                        },
                    },
                },
                upstream = {nodes = {["127.0.0.1:1980"] = 1}, type = "roundrobin"},
            })
            put("/global_rules/1", {
                id = "1",
                plugins = {
                    ["response-rewrite"] = {
                        headers = {
                            set = {["X-Global-Secret"] = mark("global-secret")},
                        },
                    },
                },
            })
            put("/routes/1", {uri = "/uri", service_id = "1"})
            ngx.sleep(0.5)

            local res = get("/uri")
            ngx.say(res.body:match("x%-service%-secret: [^\n]+"))
            ngx.say(res.headers["X-Global-Secret"])
            del("/global_rules/1")
            del("/routes/1")
            del("/services/1")
        }
    }
--- response_body
x-service-secret: service-secret
global-secret



=== TEST 6: consumer: marked key whose plaintext is itself valid ciphertext is decrypted once
--- config
    location /t {
        content_by_lua_block {
            put("/consumers/jack", {
                username = "jack",
                plugins = {
                    ["key-auth"] = {key = mark(enc("jack-key"))},
                },
            })
            put("/routes/1", {
                uri = "/hello",
                plugins = {["key-auth"] = {}},
                upstream = {nodes = {["127.0.0.1:1980"] = 1}, type = "roundrobin"},
            })
            ngx.sleep(0.5)
            ngx.say(get("/hello", {apikey = enc("jack-key")}).status)
            ngx.say(get("/hello", {apikey = "jack-key"}).status)
        }
    }
--- response_body
200
401



=== TEST 7: consumer: unmarked values keep the encrypt_fields behavior
--- config
    location /t {
        content_by_lua_block {
            put("/consumers/jack", {
                username = "jack",
                plugins = {
                    ["key-auth"] = {key = enc("jack-key")},
                },
            })
            put("/consumers/rose", {
                username = "rose",
                plugins = {
                    ["key-auth"] = {key = "rose-plain-key"},
                },
            })
            ngx.sleep(0.5)
            for _, key in ipairs({"jack-key", enc("jack-key"), "rose-plain-key"}) do
                ngx.say(get("/hello", {apikey = key}).status)
            end
            del("/consumers/rose")
        }
    }
--- response_body
200
401
200



=== TEST 8: consumer: marked value that fails to decrypt makes the consumer invalid
--- config
    location /t {
        content_by_lua_block {
            -- let the valid jack be loaded first
            ngx.sleep(0.5)
            put("/consumers/jack", {
                username = "jack",
                plugins = {
                    ["key-auth"] = {key = "$ENC$v1$not-a-ciphertext"},
                },
            })
            ngx.sleep(0.5)
            ngx.say(get("/hello", {apikey = "$ENC$v1$not-a-ciphertext"}).status)
            -- the last valid config of jack is still in effect
            ngx.say(get("/hello", {apikey = "jack-key"}).status)
            del("/consumers/jack")
            del("/routes/1")
        }
    }
--- response_body
401
200
--- error_log
failed to decrypt the value of plugin [key-auth] key [key]: base64 decode failed



=== TEST 9: plugin_metadata: decrypt a marked value
--- config
    location /t {
        content_by_lua_block {
            put("/plugin_metadata/http-logger", {
                id = "http-logger",
                log_format = {secret = mark("metadata-secret")},
            })
            ngx.sleep(0.5)

            local md = require("apisix.plugin").plugin_metadata("http-logger")
            ngx.say(md.value.log_format.secret)
        }
    }
--- response_body
metadata-secret



=== TEST 10: plugin_metadata: marked value that fails to decrypt makes the metadata invalid
--- config
    location /t {
        content_by_lua_block {
            del("/plugin_metadata/http-logger")
            ngx.sleep(0.5)
            put("/plugin_metadata/http-logger", {
                id = "http-logger",
                log_format = {secret = "$ENC$v1$" .. enc("x"):sub(2)},
            })
            ngx.sleep(0.5)

            ngx.say(require("apisix.plugin").plugin_metadata("http-logger"))
            del("/plugin_metadata/http-logger")
        }
    }
--- response_body
nil
--- error_log
failed to decrypt the value of plugin metadata [http-logger] key [log_format.secret]



=== TEST 11: stream route: decrypt a marked value in an array
--- config
    location /t {
        content_by_lua_block {
            put("/stream_routes/1", {
                plugins = {
                    ["ip-restriction"] = {whitelist = {mark("127.0.0.1")}},
                },
                upstream = {nodes = {["127.0.0.1:1995"] = 1}, type = "roundrobin"},
            })
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 12: hit the stream route
--- stream_request
mmm
--- stream_response
hello world



=== TEST 13: stream route: marked value that fails to decrypt makes the stream route invalid
--- config
    location /t {
        content_by_lua_block {
            del("/stream_routes/1")
            put("/stream_routes/2", {
                plugins = {
                    ["ip-restriction"] = {whitelist = {"$ENC$v1$" .. enc("x"):sub(2)}},
                },
                upstream = {nodes = {["127.0.0.1:1995"] = 1}, type = "roundrobin"},
            })
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 14: the invalid stream route is not loaded
--- stream_request
mmm
--- stream_response
receive stream response error: connection reset by peer
--- error_log
failed to decrypt the value of plugin [ip-restriction] key [whitelist.1]
