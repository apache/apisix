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
BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

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
stream_plugins:
    - prometheus
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

=== TEST 1: route with metrics
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                {
                    uri = "/apisix/prometheus/metrics",
                    plugins = {
                        ["public-api"] = {}
                    }
                }
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "redis",
                        conf = {
                            faults = {
                                {delay = 0.08, commands = {"hmset"}},
                                {delay = 0.3, commands = {"hmget"}},
                            }
                        },
                        metric = {
                            enable = true,
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



=== TEST 2: hit
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

            local res, err = red:hmget("animals", "dog", "cat")
            if not res then
                ngx.say("failed to get animals: ", err)
                return
            end
        }
    }
--- response_body
--- stream_conf_enable



=== TEST 3: check metrics
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_redis_commands_latency_seconds_bucket\{route="1",command="hmget",le="0.5"\} 1/ and
qr/apisix_redis_commands_latency_seconds_bucket\{route="1",command="hmset",le="0.1"\} 1/ and
qr/apisix_redis_commands_total\{route="1",command="hmget"\} 1
apisix_redis_commands_total\{route="1",command="hmset"\} 1/



=== TEST 4: ignore metric if prometheus is disabled
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
        }
    }
--- response_body
--- extra_yaml_config
stream_plugins:
    - ip-restriction
xrpc:
  protocols:
    - name: redis
--- stream_conf_enable



=== TEST 5: check metrics
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_redis_commands_total\{route="1",command="hmset"\} 1/



=== TEST 6: ignore metric if metric is disabled
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                {
                    protocol = {
                        name = "redis",
                        conf = {
                            faults = {
                                {delay = 0.08, commands = {"hmset"}},
                                {delay = 0.3, commands = {"hmget"}},
                            }
                        },
                        metric = {
                            enable = false
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

            local res, err = red:hmset("animals", "dog", "bark", "cat", "meow")
            if not res then
                ngx.say("failed to set animals: ", err)
                return
            end
        }
    }
--- response_body
--- stream_conf_enable



=== TEST 8: check metrics
--- request
GET /apisix/prometheus/metrics
--- response_body eval
qr/apisix_redis_commands_total\{route="1",command="hmset"\} 1/



=== TEST 9: remove public API route and test route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_DELETE
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 10: fetch the prometheus metric data while prometheus plugin is disabled
--- yaml_config
plugins:
  - limit-count
--- request
GET /apisix/prometheus/metrics
--- error_code: 404
