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
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;
    $block->set_value("request", "GET /t");
    $block->set_value("no_error_log", "[error]\n[alert]");
    $block->set_value("extra_init_by_lua_start", <<'_EOC_');
        local dict = ngx.shared["prometheus-metrics"]
        local every = ngx.timer.every
        ngx.timer.every = function(interval, ...)
            if interval == 21600 then
                dict:incr("test_timer_" .. require("ngx.process").type(), 1, 0)
            end
            return every(interval, ...)
        end
        local lib = require("prometheus")
        local init = lib.init
        lib.init = function(...)
            test_prometheus = init(...)
            return test_prometheus
        end
        local flush = dict.flush_expired
        dict.flush_expired = function(self, ...)
            self:incr("test_flush_" .. require("ngx.process").type(), 1, 0)
            return flush(self, ...)
        end
_EOC_
});

run_tests;

__DATA__

=== TEST 1: the privileged agent reclaims expired entries
--- extra_yaml_config
plugin_attr:
    prometheus:
        flush_expired_interval: 0.1
--- config
    location /t {
        content_by_lua_block {
            local dict = ngx.shared["prometheus-metrics"]
            assert(dict:set("test_permanent", 42))
            assert(dict:set("test_expired", 1, 0.01))
            ngx.sleep(0.5)
            assert(dict:get_stale("test_expired") == nil)
            assert(dict:get("test_permanent") == 42)
            assert((dict:get("test_flush_privileged agent") or 0) > 0)
            assert(dict:get("test_flush_worker") == nil)
            ngx.say("passed")
        }
    }
--- response_body
passed


=== TEST 2: zero disables automatic reclamation
--- extra_yaml_config
plugin_attr:
    prometheus:
        flush_expired_interval: 0
--- config
    location /t {
        content_by_lua_block {
            local dict = ngx.shared["prometheus-metrics"]
            assert(dict:set("test_permanent", 42))
            assert(dict:set("test_expired", 1, 0.01))
            ngx.sleep(0.5)
            local value, _, stale = dict:get_stale("test_expired")
            assert(value == 1 and stale)
            assert(dict:get("test_flush_privileged agent") == nil)
            assert(dict:get("test_flush_worker") == nil)
            ngx.say("passed")
        }
    }
--- response_body
passed


=== TEST 3: a negative interval disables automatic reclamation
--- extra_yaml_config
plugin_attr:
    prometheus:
        flush_expired_interval: -1
--- config
    location /t {
        content_by_lua_block {
            local dict = ngx.shared["prometheus-metrics"]
            assert(dict:set("test_permanent", 42))
            assert(dict:set("test_expired", 1, 0.01))
            ngx.sleep(0.5)
            local value, _, stale = dict:get_stale("test_expired")
            assert(value == 1 and stale)
            assert(dict:get("test_flush_privileged agent") == nil)
            assert(dict:get("test_flush_worker") == nil)
            ngx.say("passed")
        }
    }
--- response_body
passed


=== TEST 4: the default interval does not reclaim immediately
--- config
    location /t {
        content_by_lua_block {
            local dict = ngx.shared["prometheus-metrics"]
            assert(dict:set("test_permanent", 42))
            assert(dict:set("test_expired", 1, 0.01))
            ngx.sleep(0.5)
            local value, _, stale = dict:get_stale("test_expired")
            assert(value == 1 and stale)
            assert(dict:get("test_flush_privileged agent") == nil)
            assert(dict:get("test_flush_worker") == nil)
            assert(dict:get("test_timer_privileged agent") == 1)
            assert(dict:get("test_timer_worker") == nil)
            ngx.say("passed")
        }
    }
--- response_body
passed


=== TEST 5: disabling reclamation preserves local index cleanup
--- extra_yaml_config
plugin_attr:
    prometheus:
        flush_expired_interval: 0
--- config
    location /t {
        content_by_lua_block {
            local p = test_prometheus
            local index = p.key_index
            local dict = ngx.shared["prometheus-metrics"]
            local metric = p:gauge("test_local_cleanup", "Cleanup test", nil, 0.01)
            metric:set(1)
            local slot = assert(index.index.test_local_cleanup)
            local key = index.key_prefix .. slot
            ngx.sleep(0.02)
            index:remove_expired_keys()
            assert(dict:get_stale(key) ~= nil)
            assert(index.keys[slot] ~= nil)
            assert(dict:get("test_flush_worker") == nil)
            dict:delete(key)
            index:remove_expired_keys()
            assert(index.keys[slot] == nil)
            assert(index.index.test_local_cleanup == nil)
            ngx.say("passed")
        }
    }
--- response_body
passed
