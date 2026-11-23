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
    $block->set_value("request", "GET /t") unless $block->request;
    $block->set_value("no_error_log", "[error]\n[alert]") unless $block->error_log;
});

run_tests;

__DATA__

=== TEST 1: thresholds, response settings and runtime state keep each plugin's bucket
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local util = require("apisix.utils.limit")
            local cases = {
                {"limit-count", {count = 8, time_window = 60},
                    {count = 10, show_limit_quota_header = false, sync_interval = -1}},
                {"limit-conn", {conn = 8, burst = 0, default_conn_delay = 0.1,
                                key = "remote_addr"},
                    {conn = 10, burst = 2, default_conn_delay = 0.2,
                     only_use_default_delay = true}},
                {"limit-req", {rate = 8, burst = 0, key = "remote_addr"},
                    {rate = 10, burst = 2, nodelay = true}},
            }
            for _, case in ipairs(cases) do
                local plugin = require("apisix.plugins." .. case[1])
                local conf = case[2]
                assert(plugin.check_schema(conf))
                local before = util.get_bucket_id(conf)
                assert(before)
                for k, v in pairs(case[3]) do
                    conf[k] = v
                end
                conf.rejected_code = 429
                conf.rejected_msg = "try later"
                conf.allow_degradation = true
                conf._meta.priority = 1234
                conf._meta.error_response = "too many requests"
                conf._version = "runtime version"
                assert(plugin.check_schema(conf))
                assert(before == util.get_bucket_id(conf), case[1])
                assert(conf.rejected_msg == "try later")
                ngx.say(case[1], ": kept")
            end
        }
    }
--- response_body
limit-count: kept
limit-conn: kept
limit-req: kept



=== TEST 2: counting keys and selection change the bucket
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local util = require("apisix.utils.limit")
            for _, name in ipairs({"limit-count", "limit-conn", "limit-req"}) do
                local plugin = require("apisix.plugins." .. name)
                local conf = name == "limit-count" and {count = 8, time_window = 60}
                             or name == "limit-conn"
                                and {conn = 8, burst = 0, default_conn_delay = 0.1,
                                     key = "remote_addr"}
                             or {rate = 8, burst = 0, key = "remote_addr"}
                assert(plugin.check_schema(conf))
                local id = util.get_bucket_id(conf)
                local changed = core.table.deepcopy(conf)
                changed.key = "http_x_user"
                assert(plugin.check_schema(changed))
                assert(id ~= util.get_bucket_id(changed))
                changed = core.table.deepcopy(conf)
                changed._meta.filter = {{"request_method", "==", "POST"}}
                assert(plugin.check_schema(changed))
                assert(id ~= util.get_bucket_id(changed))
                changed = core.table.deepcopy(conf)
                changed._meta.pre_function = "return function(conf, ctx) end"
                assert(plugin.check_schema(changed))
                assert(id ~= util.get_bucket_id(changed))
                assert(id == util.get_bucket_id(conf), "a copy must not mutate its source")
                ngx.say(name, ": isolated")
            end
        }
    }
--- response_body
limit-count: isolated
limit-conn: isolated
limit-req: isolated



=== TEST 3: multi-rule projections keep limits and headers out of the identity
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local util = require("apisix.utils.limit")
            local plugin = require("apisix.plugins.limit-count")
            local conf = {rules = {
                {key = "$remote_addr", count = 8, time_window = 60},
                {key = "$host", count = 10, time_window = 120},
            }}
            assert(plugin.check_schema(conf))
            local id = util.get_bucket_id(conf)
            conf.rules[2].count = 20
            conf.rules[1].header_prefix = "client"
            assert(plugin.check_schema(conf))
            assert(id == util.get_bucket_id(conf))
            assert(conf.rules[2].count == 20)
            local changed = core.table.deepcopy(conf)
            changed.rules[2].time_window = 180
            assert(plugin.check_schema(changed))
            assert(id ~= util.get_bucket_id(changed))
            changed = core.table.deepcopy(conf)
            changed.rules[1].key = "$http_x_user"
            assert(plugin.check_schema(changed))
            assert(id ~= util.get_bucket_id(changed))
            conf = {count = 8, time_window = 60}
            assert(plugin.check_schema(conf))
            id = util.get_bucket_id(conf)
            conf.window_type = "sliding"
            assert(plugin.check_schema(conf))
            assert(id ~= util.get_bucket_id(conf))
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 4: equivalent defaults and object order have the same identity
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local util = require("apisix.utils.limit")
            local plugin = require("apisix.plugins.limit-count")
            local a = {count = 8, time_window = 60}
            local b = {time_window = 60, count = 10, key = "remote_addr", key_type = "var",
                       policy = "local", window_type = "fixed"}
            assert(plugin.check_schema(a))
            assert(plugin.check_schema(b))
            assert(util.get_bucket_id(a) == util.get_bucket_id(b))
            local paths = {"$['a','b']"}
            local x, y = {a = "same"}, {b = "same"}
            assert(util.prepare_bucket_id(x, paths))
            assert(util.prepare_bucket_id(y, paths))
            assert(util.get_bucket_id(x) ~= util.get_bucket_id(y), "field names matter")
            local c, d = {a = {x = 1, y = core.json.null}},
                         {a = {y = core.json.null, x = 1}}
            assert(util.prepare_bucket_id(c, paths))
            assert(util.prepare_bucket_id(d, paths))
            assert(util.get_bucket_id(c) == util.get_bucket_id(d))
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 5: Redis connection tuning preserves identity, another database does not
--- config
    location /t {
        content_by_lua_block {
            local util = require("apisix.utils.limit")
            local plugin = require("apisix.plugins.limit-count")
            local conf = {count = 8, time_window = 60, policy = "redis",
                          redis_host = "127.0.0.1"}
            assert(plugin.check_schema(conf))
            local id = util.get_bucket_id(conf)
            conf.redis_username = "new-user"
            conf.redis_password = "new-password"
            conf.redis_timeout = 500
            conf.redis_ssl = true
            conf.redis_ssl_verify = true
            conf.redis_server_name = "redis.example.com"
            conf.redis_keepalive_timeout = 20000
            conf.redis_keepalive_pool = 50
            assert(plugin.check_schema(conf))
            assert(id == util.get_bucket_id(conf))
            conf.redis_database = 1
            assert(plugin.check_schema(conf))
            assert(id ~= util.get_bucket_id(conf))
            id = util.get_bucket_id(conf)
            conf.redis_port = 6380
            assert(plugin.check_schema(conf))
            assert(id ~= util.get_bucket_id(conf))
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 6: cluster and Sentinel endpoints are canonicalized without changing the configuration
--- config
    location /t {
        content_by_lua_block {
            local util = require("apisix.utils.limit")
            local plugin = require("apisix.plugins.limit-count")
            local conf = {count = 8, time_window = 60, policy = "redis-cluster",
                          redis_cluster_name = "cluster",
                          redis_cluster_nodes = {"127.0.0.1:5001", "127.0.0.1:5000"}}
            assert(plugin.check_schema(conf))
            assert(conf.redis_cluster_nodes[1] == "127.0.0.1:5001")
            local id = util.get_bucket_id(conf)
            conf.redis_cluster_nodes = {"127.0.0.1:5000", "127.0.0.1:5001"}
            assert(plugin.check_schema(conf))
            assert(id == util.get_bucket_id(conf))
            conf.redis_cluster_name = "other-cluster"
            assert(plugin.check_schema(conf))
            assert(id ~= util.get_bucket_id(conf))
            conf = {count = 8, time_window = 60, policy = "redis-sentinel",
                    redis_master_name = "master", redis_sentinels = {
                        {host = "127.0.0.1", port = 26380},
                        {host = "127.0.0.1", port = 26379},
                    }}
            assert(plugin.check_schema(conf))
            assert(conf.redis_sentinels[1].port == 26380)
            id = util.get_bucket_id(conf)
            conf.redis_sentinels = {conf.redis_sentinels[2], conf.redis_sentinels[1]}
            conf.sentinel_username = "new-user"
            conf.sentinel_password = "new-password"
            assert(plugin.check_schema(conf))
            assert(id == util.get_bucket_id(conf))
            conf.redis_master_name = "other-master"
            assert(plugin.check_schema(conf))
            assert(id ~= util.get_bucket_id(conf))
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 7: bucket metadata is runtime-only and compatible with parent injection and rechecking
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local util = require("apisix.utils.limit")
            local plugin = require("apisix.plugins.limit-count")
            local conf = {count = 8, time_window = 60}
            assert(plugin.check_schema(conf))
            local id = util.get_bucket_id(conf)
            require("apisix.plugin").set_plugins_meta_parent({["limit-count"] = conf}, {
                key = "/apisix/routes/bucket-test", modifiedIndex = 42,
            })
            assert(conf._meta.parent.resource_key == "/apisix/routes/bucket-test")
            assert(conf._meta.bucket_id == id)
            assert(rawget(conf._meta, "bucket_id") == nil)
            local serialized = core.json.encode(conf)
            assert(not serialized:find("bucket_id", 1, true))
            assert(not serialized:find("resource_key", 1, true))
            assert(plugin.check_schema(conf))
            assert(util.get_bucket_id(conf) == id)
            assert(conf._meta.parent.resource_version == "42")
            local copied = core.table.deepcopy(conf)
            assert(util.get_bucket_id(copied) == id)
            copied.time_window = 120
            assert(plugin.check_schema(copied))
            assert(util.get_bucket_id(copied) ~= id)
            assert(util.get_bucket_id(conf) == id)
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 8: invalid configurations and plugin metadata do not get a bucket
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local util = require("apisix.utils.limit")
            local plugin = require("apisix.plugins.limit-count")
            local conf = {count = 0, time_window = 60}
            assert(not plugin.check_schema(conf))
            assert(not util.get_bucket_id(conf))
            conf = {limit_header = "X-Custom-Limit"}
            assert(plugin.check_schema(conf, core.schema.TYPE_METADATA))
            assert(not util.get_bucket_id(conf))
            conf = {key = "client"}
            assert(not util.prepare_bucket_id(conf, {"$["}))
            assert(not util.get_bucket_id(conf))
            assert(util.prepare_bucket_id(conf, {"$.key"}))
            assert(util.get_bucket_id(conf))
            ngx.say("passed")
        }
    }
--- response_body
passed
