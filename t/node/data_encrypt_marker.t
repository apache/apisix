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
    function _G.create_redis_user()
        -- not every CI job starts Redis with an ACL user, so create one here
        local red = require("resty.redis"):new()
        assert(red:connect("127.0.0.1", 6379))
        assert(red:acl("setuser", "enc-marker", "reset", "on",
                       ">enc-marker-pass", "~*", "&*", "+\@all"))
        red:close()
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
--- no_error_log
[error]



=== TEST 2: hit the route
--- request
GET /uri
--- response_body
uri: /uri
host: localhost
x-real-ip: 127.0.0.1
x-secret: route-secret
--- no_error_log
[error]



=== TEST 3: marked value that fails to decrypt is logged and kept as it is
--- config
    location /t {
        content_by_lua_block {
            put("/routes/1", {
                uri = "/uri",
                plugins = {
                    ["proxy-rewrite"] = {
                        headers = {
                            set = {["X-Secret"] = "$ENC$v1$" .. enc("x"):sub(2)},
                        },
                    },
                },
                upstream = {nodes = {["127.0.0.1:1980"] = 1}, type = "roundrobin"},
            })
            ngx.sleep(0.5)
            -- the route is loaded and the header is set from the value as stored
            ngx.say(get("/uri").body:match("x%-secret: [^\n]*") ~= nil)
            del("/routes/1")
        }
    }
--- response_body
true
--- error_log
failed to decrypt the value of plugin [proxy-rewrite] key [headers.set.X-Secret]



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
--- no_error_log
[error]



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
--- no_error_log
[error]



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



=== TEST 8: consumer: marked value that fails to decrypt is logged and kept as it is
--- config
    location /t {
        content_by_lua_block {
            put("/consumers/jack", {
                username = "jack",
                plugins = {
                    ["key-auth"] = {key = "$ENC$v1$not-a-ciphertext"},
                },
            })
            ngx.sleep(0.5)
            ngx.say(get("/hello", {apikey = "$ENC$v1$not-a-ciphertext"}).status)
            ngx.say(get("/hello", {apikey = "jack-key"}).status)
            del("/consumers/jack")
            del("/routes/1")
        }
    }
--- response_body
200
401
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
--- no_error_log
[error]



=== TEST 10: plugin_metadata: marked value that fails to decrypt is logged and kept as it is
--- config
    location /t {
        content_by_lua_block {
            local bad = "$ENC$v1$" .. enc("x"):sub(2)
            put("/plugin_metadata/http-logger", {
                id = "http-logger",
                log_format = {secret = bad},
            })
            ngx.sleep(0.5)

            local md = require("apisix.plugin").plugin_metadata("http-logger")
            ngx.say(md.value.log_format.secret == bad)
            del("/plugin_metadata/http-logger")
        }
    }
--- response_body
true
--- error_log
failed to decrypt the value of plugin [http-logger] key [log_format.secret]



=== TEST 11: plugin_metadata: a decrypted marked value is not logged when the schema check fails
--- config
    location /t {
        content_by_lua_block {
            put("/plugin_metadata/http-logger", {
                id = "http-logger",
                log_format = {secret = mark("metadata-secret")},
                log_format_extra = "not-an-object",
            })
            ngx.sleep(0.5)

            ngx.say(require("apisix.plugin").plugin_metadata("http-logger"))
            del("/plugin_metadata/http-logger")
        }
    }
--- response_body
nil
--- error_log
failed to check item data of [/apisix/plugin_metadata]
--- no_error_log
metadata-secret



=== TEST 12: stream route: decrypt a marked value in an array
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



=== TEST 13: hit the stream route
--- stream_request
mmm
--- stream_response
hello world



=== TEST 14: stream route: marked value that fails to decrypt is kept and validated as it is
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



=== TEST 15: the stream route with the kept value is not loaded
--- stream_request
mmm
--- stream_response
receive stream response error: connection reset by peer
--- error_log
failed to decrypt the value of plugin [ip-restriction] key [whitelist.1]



=== TEST 16: stream route: limit-conn authenticates to Redis with a marked password
--- config
    location /t {
        content_by_lua_block {
            create_redis_user()
            del("/stream_routes/2")
            put("/stream_routes/1", {
                plugins = {
                    ["limit-conn"] = {
                        conn = 1,
                        burst = 0,
                        default_conn_delay = 0.1,
                        key = "remote_addr",
                        policy = "redis",
                        redis_host = "127.0.0.1",
                        redis_port = 6379,
                        redis_database = 0,
                        redis_timeout = 1000,
                        key_ttl = 3600,
                        redis_username = "enc-marker",
                        redis_password = mark("enc-marker-pass"),
                    },
                },
                upstream = {nodes = {["127.0.0.1:1995"] = 1}, type = "roundrobin"},
            })
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 17: hit the stream route with limit-conn
--- stream_request
mmm
--- stream_response
hello world
--- no_error_log
[error]
failed to limit conn



=== TEST 18: stream route: the held connection is counted in Redis and limits the next one
--- stream_upstream_code
            local sock = ngx.req.socket()
            sock:receive("1")

            -- runs while the proxied connection holds the only slot
            local redis = require("resty.redis")
            local red = redis:new()
            assert(red:connect("127.0.0.1", 6379))
            assert(red:auth("enc-marker", "enc-marker-pass"))
            local keys = assert(red:keys("limit_conn:/apisix/stream_routes/1:*"))
            local held = 0
            for _, key in ipairs(keys) do
                held = held + assert(red:zcard(key))
            end

            local second = ngx.socket.tcp()
            second:settimeout(2000)
            assert(second:connect("127.0.0.1", 1985))
            assert(second:send("mmm"))
            local data = second:receive("*a")
            second:close()

            ngx.say("held: ", held, ", second rejected: ", data == nil)
--- stream_request
mmm
--- stream_response
held: 1, second rejected: true
--- error_log
limit-conn exits with status code 503



=== TEST 19: stream route: limit-conn with a marked password Redis rejects
--- config
    location /t {
        content_by_lua_block {
            put("/stream_routes/1", {
                plugins = {
                    ["limit-conn"] = {
                        conn = 1,
                        burst = 0,
                        default_conn_delay = 0.1,
                        key = "remote_addr",
                        policy = "redis",
                        redis_host = "127.0.0.1",
                        redis_port = 6379,
                        redis_database = 0,
                        redis_timeout = 1000,
                        key_ttl = 3600,
                        redis_username = "enc-marker",
                        redis_password = mark("wrong-pass"),
                    },
                },
                upstream = {nodes = {["127.0.0.1:1995"] = 1}, type = "roundrobin"},
            })
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 20: the stream route with the wrong Redis password rejects the connection
--- stream_request
mmm
--- stream_response
receive stream response error: connection reset by peer
--- error_log
failed to limit conn: WRONGPASS



=== TEST 21: stream service: limit-conn authenticates to Redis with a marked password
--- config
    location /t {
        content_by_lua_block {
            create_redis_user()
            put("/services/1", {
                plugins = {
                    ["limit-conn"] = {
                        conn = 1,
                        burst = 0,
                        default_conn_delay = 0.1,
                        key = "remote_addr",
                        policy = "redis",
                        redis_host = "127.0.0.1",
                        redis_port = 6379,
                        redis_database = 0,
                        redis_timeout = 1000,
                        key_ttl = 3600,
                        redis_username = "enc-marker",
                        redis_password = mark("enc-marker-pass"),
                    },
                },
                upstream = {nodes = {["127.0.0.1:1995"] = 1}, type = "roundrobin"},
            })
            put("/stream_routes/1", {service_id = "1"})
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 22: hit the stream route through the stream service
--- stream_request
mmm
--- stream_response
hello world
--- no_error_log
[error]
failed to limit conn



=== TEST 23: stream service: the held connection is counted in Redis and limits the next one
--- stream_upstream_code
            local sock = ngx.req.socket()
            sock:receive("1")

            -- runs while the proxied connection holds the only slot
            local redis = require("resty.redis")
            local red = redis:new()
            assert(red:connect("127.0.0.1", 6379))
            assert(red:auth("enc-marker", "enc-marker-pass"))
            local keys = assert(red:keys("limit_conn:/apisix/services/1:*"))
            local held = 0
            for _, key in ipairs(keys) do
                held = held + assert(red:zcard(key))
            end

            local second = ngx.socket.tcp()
            second:settimeout(2000)
            assert(second:connect("127.0.0.1", 1985))
            assert(second:send("mmm"))
            local data = second:receive("*a")
            second:close()

            ngx.say("held: ", held, ", second rejected: ", data == nil)
--- stream_request
mmm
--- stream_response
held: 1, second rejected: true
--- error_log
limit-conn exits with status code 503
