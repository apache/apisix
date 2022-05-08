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
