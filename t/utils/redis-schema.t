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

});

run_tests();

__DATA__

=== TEST 1: limit-count/limit-req validation must not pick up limit-conn's key_ttl
--- config
    location /t {
        content_by_lua_block {
            -- limit-conn extends the shared redis/redis-cluster schemas with
            -- key_ttl. Load it first so that any leak of key_ttl into the
            -- shared tables of apisix.utils.redis-schema would be visible
            -- to the other rate limiting plugins below.
            require("apisix.plugins.limit-conn")

            local cases = {
                {
                    plugin = "limit-count",
                    conf = {
                        count = 2,
                        time_window = 60,
                        policy = "redis",
                        redis_host = "127.0.0.1",
                    },
                },
                {
                    plugin = "limit-count",
                    conf = {
                        count = 2,
                        time_window = 60,
                        policy = "redis-cluster",
                        redis_cluster_nodes = {"127.0.0.1:5000", "127.0.0.1:5001"},
                        redis_cluster_name = "redis-cluster-1",
                    },
                },
                {
                    plugin = "limit-req",
                    conf = {
                        rate = 1,
                        burst = 0,
                        key = "remote_addr",
                        policy = "redis",
                        redis_host = "127.0.0.1",
                    },
                },
                {
                    plugin = "limit-req",
                    conf = {
                        rate = 1,
                        burst = 0,
                        key = "remote_addr",
                        policy = "redis-cluster",
                        redis_cluster_nodes = {"127.0.0.1:5000", "127.0.0.1:5001"},
                        redis_cluster_name = "redis-cluster-1",
                    },
                },
            }

            for _, case in ipairs(cases) do
                local plugin = require("apisix.plugins." .. case.plugin)
                local ok, err = plugin.check_schema(case.conf)
                if not ok then
                    ngx.say(err)
                elseif case.conf.key_ttl ~= nil then
                    ngx.say(case.plugin, " ", case.conf.policy,
                            " got key_ttl: ", case.conf.key_ttl)
                else
                    ngx.say("passed")
                end
            end
            ngx.say("done")
        }
    }
--- response_body
passed
passed
passed
passed
done



=== TEST 2: limit-conn still defaults key_ttl to 3600 and honors an explicit value
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.limit-conn")

            local conf = {
                conn = 1,
                burst = 0,
                default_conn_delay = 0.1,
                key = "remote_addr",
                policy = "redis",
                redis_host = "127.0.0.1",
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say(conf.key_ttl)

            conf = {
                conn = 1,
                burst = 0,
                default_conn_delay = 0.1,
                key = "remote_addr",
                policy = "redis-cluster",
                redis_cluster_nodes = {"127.0.0.1:5000", "127.0.0.1:5001"},
                redis_cluster_name = "redis-cluster-1",
                key_ttl = 60,
            }
            ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say(conf.key_ttl)
        }
    }
--- response_body
3600
60
