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

    $ENV{REDIS_HOST} = "127.0.0.1";
}

use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: modified redis script, cost == 2
--- config
    location /t {
        content_by_lua_block {
            local conf = {
                allow_degradation = false,
                rejected_code = 503,
                redis_timeout = 1000,
                key_type = "var",
                time_window = 60,
                show_limit_quota_header = true,
                count = 3,
                redis_host = "127.0.0.1",
                redis_port = 6379,
                redis_database = 0,
                policy = "redis",
                key = "remote_addr"
            }

            local lim_count_redis = require("apisix.plugins.limit-count.limit-count-redis")
            local lim = lim_count_redis.new("limit-count", 3, 60, conf)
            local uri = ngx.var.uri
            local _, remaining, _ = lim:incoming(uri, 2)

            ngx.say("remaining: ", remaining)
        }
    }
--- response_body
remaining: 1



=== TEST 2: set route, with redis host as environment variable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 2,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "$remote_addr testcase_4_2",
                            "key_type":"var_combination",
                            "policy": "redis",
                            "redis_host": "$ENV://REDIS_HOST"
                        }
                    },
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



=== TEST 3: up the limit with host environment variable
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503]



=== TEST 4: set route for keepalive test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "limit-count": {
                            "count": 20,
                            "time_window": 1,
                            "rejected_code": 503,
                            "key": "remote_addr",
                            "show_limit_quota_header":false,
                            "policy": "redis",
                            "redis_host": "$ENV://REDIS_HOST"
                        }
                    },
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



=== TEST 5: verify redis keepalive
--- extra_init_by_lua
    local limit_count = require("apisix.plugins.limit-count.limit-count-redis")
    local core = require("apisix.core")

    limit_count.origin_incoming = limit_count.incoming
    limit_count.incoming = function(self, key, commit)
        local redis = require("resty.redis")
        local conf = self.conf
        local delay, err = self:origin_incoming(key, commit)
        if not delay then
            ngx.say("limit fail: ", err)
            return delay, err
        end

        -- verify connection reused time
        local red,err = redis:new()
        if err then
            core.log.error("failed to create redis cli: ", err)
            ngx.say("failed to create redis cli: ", err)
            return nil, err
        end
        red:set_timeout(1000)
        local ok, err = red:connect(conf.redis_host, conf.redis_port)
        if not ok then
            core.log.error("failed to connect: ", err)
            ngx.say("failed to connect: ", err)
            return nil, err
        end
        local reused_time, err = red:get_reused_times()
        if reused_time == 0 then
            core.log.error("redis connection is not keepalive")
            ngx.say("redis connection is not keepalive")
            return nil, err
        end

        red:close()
        ngx.say("redis connection has set keepalive")
        return delay, err
    end
--- request
GET /hello
--- response_body
redis connection has set keepalive
