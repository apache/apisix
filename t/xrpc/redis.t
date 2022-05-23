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
use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

$ENV{TEST_NGINX_REDIS_PORT} ||= 1985;

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->extra_yaml_config) {
        my $extra_yaml_config = <<_EOC_;
xrpc:
  protocols:
    - name: redis
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]\nRPC is not finished");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    $block;
});

worker_connections(1024);
run_tests;

__DATA__

=== TEST 1: init
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "redis"
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:6379"] = 1
                        },
                        type = "roundrobin"
                    }
                }
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: sanity
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = red:hmset("animals", "dog", "bark", "cat", "meow")
            if not res then
                ngx.say("failed to set animals: ", err)
                return
            end
            ngx.say("hmset animals: ", res)

            local res, err = red:hmget("animals", "dog", "cat")
            if not res then
                ngx.say("failed to get animals: ", err)
                return
            end

            ngx.say("hmget animals: ", res)

            local res, err = red:hget("animals", "dog")
            if not res then
                ngx.say("failed to get animals: ", err)
                return
            end

            ngx.say("hget animals: ", res)

            local res, err = red:hget("animals", "not_found")
            if not res then
                ngx.say("failed to get animals: ", err)
                return
            end

            ngx.say("hget animals: ", res)
        }
    }
--- response_body
hmset animals: OK
hmget animals: barkmeow
hget animals: bark
hget animals: null
--- stream_conf_enable



=== TEST 3: error
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = red:get("animals")
            if not res then
                ngx.say("failed to set animals: ", err)
            end

            local res, err = red:hget("animals", "dog")
            if not res then
                ngx.say("failed to get animals: ", err)
                return
            end

            ngx.say("hget animals: ", res)
        }
    }
--- response_body
failed to set animals: WRONGTYPE Operation against a key holding the wrong kind of value
hget animals: bark
--- stream_conf_enable



=== TEST 4: big value
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = red:set("big-key", ("\r\n"):rep(1024 * 1024 * 16))
            if not res then
                ngx.say("failed to set: ", err)
                return
            end

            local res, err = red:get("big-key")
            if not res then
                ngx.say("failed to get: ", err)
                return
            end

            ngx.print(res)
        }
    }
--- response_body eval
"\r\n" x 16777216
--- stream_conf_enable



=== TEST 5: pipeline
--- config
    location /t {
        content_by_lua_block {
            local cjson = require("cjson")
            local redis = require "resty.redis"

            local t = {}
            for i = 1, 180 do
                local th = assert(ngx.thread.spawn(function(i)
                    local red = redis:new()
                    local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
                    if not ok then
                        ngx.say("failed to connect: ", err)
                        return
                    end

                    red:init_pipeline()

                    red:set("mark_" .. i, i)
                    red:get("mark_" .. i)
                    red:get("counter")
                    for j = 1, 4 do
                        red:incr("counter")
                    end

                    local results, err = red:commit_pipeline()
                    if not results then
                        ngx.say("failed to commit: ", err)
                        return
                    end

                    local begin = tonumber(results[3])
                    for j = 1, 4 do
                        local incred = results[3 + j]
                        if incred ~= results[2 + j] + 1 then
                            ngx.log(ngx.ERR, cjson.encode(results))
                        end
                    end
                end, i))
                table.insert(t, th)
            end
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
            end
        }
    }
--- response_body
--- stream_conf_enable



=== TEST 6: delay
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "redis",
                        conf = {
                            faults = {
                                {delay = 0.01, key = "ignored", commands = {"Ping", "time"}}
                            }
                        }
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:6379"] = 1
                        },
                        type = "roundrobin"
                    }
                }
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 7: hit
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local start = ngx.now()
            local res, err = red:ping()
            if not res then
                ngx.say(err)
                return
            end
            local now = ngx.now()
            -- use integer to bypass float point number precision problem
            if math.ceil((now - start) * 1000) < 10 then
                ngx.say(now, " ", start)
                return
            end
            start = now

            local res, err = red:time()
            if not res then
                ngx.say(err)
                return
            end
            local now = ngx.now()
            if math.ceil((now - start) * 1000) < 10 then
                ngx.say(now, " ", start)
                return
            end
            start = now

            red:init_pipeline()
            red:time()
            red:time()
            red:get("A")

            local results, err = red:commit_pipeline()
            if not results then
                ngx.say("failed to commit: ", err)
                return
            end
            local now = ngx.now()
            if math.ceil((now - start) * 1000) < 20 or math.ceil((now - start) * 1000) > 30 then
                ngx.say(now, " ", start)
                return
            end

            ngx.say("ok")
        }
    }
--- response_body
ok
--- stream_conf_enable



=== TEST 8: DFS match
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "redis",
                        conf = {
                            faults = {
                                {delay = 0.02, key = "a", commands = {"get"}},
                                {delay = 0.01, commands = {"get", "set"}},
                            }
                        }
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:6379"] = 1
                        },
                        type = "roundrobin"
                    }
                }
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 9: hit
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local start = ngx.now()
            local res, err = red:get("a")
            if not res then
                ngx.say(err)
                return
            end
            local now = ngx.now()
            if math.ceil((now - start) * 1000) < 20 then
                ngx.say(now, " ", start)
                return
            end
            start = now

            local res, err = red:set("a", "a")
            if not res then
                ngx.say(err)
                return
            end
            local now = ngx.now()
            if math.ceil((now - start) * 1000) < 10 then
                ngx.say(now, " ", start)
                return
            end
            start = now

            red:init_pipeline()
            red:get("b")
            red:set("A", "a")

            local results, err = red:commit_pipeline()
            if not results then
                ngx.say("failed to commit: ", err)
                return
            end
            local now = ngx.now()
            if math.ceil((now - start) * 1000) < 20 or math.ceil((now - start) * 1000) > 30 then
                ngx.say(now, " ", start)
                return
            end

            ngx.say("ok")
        }
    }
--- response_body
ok
--- stream_conf_enable



=== TEST 10: multi keys
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local etcd = require("apisix.core.etcd")
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "redis",
                        conf = {
                            faults = {
                                {delay = 0.06, key = "b", commands = {"del"}},
                                {delay = 0.04, key = "a", commands = {"mset"}},
                                {delay = 0.02, key = "b", commands = {"mset"}},
                            }
                        }
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:6379"] = 1
                        },
                        type = "roundrobin"
                    }
                }
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: hit
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local start = ngx.now()
            local res, err = red:mset("c", 1, "a", 2, "b", 3)
            if not res then
                ngx.say(err)
                return
            end
            local now = ngx.now()
            if math.ceil((now - start) * 1000) < 40 then
                ngx.say("mset a ", now, " ", start)
                return
            end
            start = now

            local res, err = red:mset("b", 2, "a", 3)
            if not res then
                ngx.say(err)
                return
            end
            local now = ngx.now()
            if math.ceil((now - start) * 1000) < 20 or math.ceil((now - start) * 1000) > 35 then
                ngx.say("mset b ", now, " ", start)
                return
            end
            start = now

            local res, err = red:mset("c", "a")
            if not res then
                ngx.say(err)
                return
            end
            local now = ngx.now()
            if math.ceil((now - start) * 1000) > 20 then
                ngx.say("mset mismatch ", now, " ", start)
                return
            end
            start = now

            local res, err = red:del("a", "b")
            if not res then
                ngx.say(err)
                return
            end
            local now = ngx.now()
            if math.ceil((now - start) * 1000) < 60 then
                ngx.say("del b ", now, " ", start)
                return
            end
            start = now

            ngx.say("ok")
        }
    }
--- response_body
ok
--- stream_conf_enable



=== TEST 12: publish & subscribe
--- stream_extra_init_by_lua
            local cjson = require "cjson"
            local redis_proto = require("apisix.stream.xrpc.protocols.redis")
            redis_proto.log = function(sess, ctx)
                ngx.log(ngx.WARN, "log redis request ", cjson.encode(ctx.cmd_line))
            end

--- config
    location /t {
        content_by_lua_block {
            local cjson = require "cjson"
            local redis = require "resty.redis"

            local red = redis:new()
            local red2 = redis:new()

            red:set_timeout(1000) -- 1 sec
            red2:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("1: failed to connect: ", err)
                return
            end

            ok, err = red2:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("2: failed to connect: ", err)
                return
            end

            local res, err = red:subscribe("dog")
            if not res then
                ngx.say("1: failed to subscribe: ", err)
                return
            end

            ngx.say("1: subscribe dog: ", cjson.encode(res))

            res, err = red:subscribe("cat")
            if not res then
                ngx.say("1: failed to subscribe: ", err)
                return
            end

            ngx.say("1: subscribe cat: ", cjson.encode(res))

            res, err = red2:publish("dog", "Hello")
            if not res then
                ngx.say("2: failed to publish: ", err)
                return
            end

            ngx.say("2: publish: ", cjson.encode(res))

            res, err = red:read_reply()
            if not res then
                ngx.say("1: failed to read reply: ", err)
            else
                ngx.say("1: receive: ", cjson.encode(res))
            end

            red:set_timeout(10) -- 10ms
            res, err = red:read_reply()
            if not res then
                ngx.say("1: failed to read reply: ", err)
            else
                ngx.say("1: receive: ", cjson.encode(res))
            end
            red:set_timeout(1000) -- 1s

            res, err = red:unsubscribe()
            if not res then
                ngx.say("1: failed to unscribe: ", err)
            else
                ngx.say("1: unsubscribe: ", cjson.encode(res))
            end

            res, err = red:read_reply()
            if not res then
                ngx.say("1: failed to read reply: ", err)
            else
                ngx.say("1: receive: ", cjson.encode(res))
            end

            red:set_timeout(10) -- 10ms
            res, err = red:read_reply()
            if not res then
                ngx.say("1: failed to read reply: ", err)
            else
                ngx.say("1: receive: ", cjson.encode(res))
            end
            red:set_timeout(1000) -- 1s

            res, err = red:set("dog", 1)
            if not res then
                ngx.say("1: failed to set: ", err)
            else
                ngx.say("1: receive: ", cjson.encode(res))
            end

            red:close()
            red2:close()
        }
    }
--- response_body_like chop
^1: subscribe dog: \["subscribe","dog",1\]
1: subscribe cat: \["subscribe","cat",2\]
2: publish: 1
1: receive: \["message","dog","Hello"\]
1: failed to read reply: timeout
1: unsubscribe: \[\["unsubscribe","(?:dog|cat)",1\],\["unsubscribe","(?:dog|cat)",0\]\]
1: failed to read reply: not subscribed
1: failed to read reply: not subscribed
1: receive: "OK"
$
--- stream_conf_enable
--- grep_error_log eval
qr/log redis request \[[^]]+\]/
--- grep_error_log_out
log redis request ["subscribe","dog"]
log redis request ["subscribe","cat"]
log redis request ["publish","dog","Hello"]
log redis request ["unsubscribe"]
log redis request ["set","dog","1"]



=== TEST 13: psubscribe & punsubscribe
--- stream_extra_init_by_lua
            local cjson = require "cjson"
            local redis_proto = require("apisix.stream.xrpc.protocols.redis")
            redis_proto.log = function(sess, ctx)
                ngx.log(ngx.WARN, "log redis request ", cjson.encode(ctx.cmd_line))
            end

--- config
    location /t {
        content_by_lua_block {
            local cjson = require "cjson"
            local redis = require "resty.redis"

            local red = redis:new()
            local red2 = redis:new()

            red:set_timeout(1000) -- 1 sec
            red2:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("1: failed to connect: ", err)
                return
            end

            ok, err = red2:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("2: failed to connect: ", err)
                return
            end

            local res, err = red:psubscribe("dog*", "cat*")
            if not res then
                ngx.say("1: failed to subscribe: ", err)
                return
            end

            ngx.say("1: psubscribe: ", cjson.encode(res))

            res, err = red2:publish("dog1", "Hello")
            if not res then
                ngx.say("2: failed to publish: ", err)
                return
            end

            ngx.say("2: publish: ", cjson.encode(res))

            res, err = red:read_reply()
            if not res then
                ngx.say("1: failed to read reply: ", err)
            else
                ngx.say("1: receive: ", cjson.encode(res))
            end

            res, err = red:punsubscribe("cat*", "dog*")
            if not res then
                ngx.say("1: failed to unscribe: ", err)
            else
                ngx.say("1: punsubscribe: ", cjson.encode(res))
            end

            res, err = red:set("dog", 1)
            if not res then
                ngx.say("1: failed to set: ", err)
            else
                ngx.say("1: receive: ", cjson.encode(res))
            end

            red:close()
            red2:close()
        }
    }
--- response_body_like chop
^1: psubscribe: \[\["psubscribe","dog\*",1\],\["psubscribe","cat\*",2\]\]
2: publish: 1
1: receive: \["pmessage","dog\*","dog1","Hello"\]
1: punsubscribe: \[\["punsubscribe","cat\*",1\],\["punsubscribe","dog\*",0\]\]
1: receive: "OK"
$
--- stream_conf_enable
--- grep_error_log eval
qr/log redis request \[[^]]+\]/
--- grep_error_log_out
log redis request ["psubscribe","dog*","cat*"]
log redis request ["publish","dog1","Hello"]
log redis request ["punsubscribe","cat*","dog*"]
log redis request ["set","dog","1"]
