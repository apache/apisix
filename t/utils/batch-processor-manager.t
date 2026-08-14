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

log_level('info');
repeat_each(1);
no_long_string();
no_root_location();
run_tests;

__DATA__

=== TEST 1: the backlog is capped even with no plugin metadata configured
--- config
    location /t {
        content_by_lua_block {
            local bp_manager_mod = require("apisix.utils.batch-processor-manager")
            local bp_manager = bp_manager_mod.new("test logger", "test-logger")
            -- a batch that is never flushed, so every accepted entry stays pending
            local conf = {
                name = "test logger",
                batch_max_size = 10000000,
                inactive_timeout = 300,
                buffer_duration = 300,
                max_retry_count = 0,
                retry_delay = 1,
            }
            local ctx = {var = {route_id = "1", server_addr = "127.0.0.1"}}
            local func = function() return true end

            local accepted = 0
            for i = 1, 20000 do
                local ok = bp_manager:add_entry(conf, i)
                if not ok then
                    ok = bp_manager:add_entry_to_new_processor(conf, i, ctx, func)
                end
                if ok then
                    accepted = accepted + 1
                end
            end
            ngx.say("accepted: ", accepted)
        }
    }
--- request
GET /t
--- response_body
accepted: 16385
--- error_log
max pending entries limit exceeded. discarding entry



=== TEST 2: max_pending_entries in the plugin's metadata overrides the default
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugin")
            plugin.plugin_metadatas = {
                get = function(self, name)
                    if name == "test-logger" then
                        return {value = {max_pending_entries = 3}}
                    end
                end
            }

            local bp_manager_mod = require("apisix.utils.batch-processor-manager")
            local bp_manager = bp_manager_mod.new("test logger", "test-logger")
            local conf = {
                name = "test logger",
                batch_max_size = 10000000,
                inactive_timeout = 300,
                buffer_duration = 300,
                max_retry_count = 0,
                retry_delay = 1,
            }
            local ctx = {var = {route_id = "1", server_addr = "127.0.0.1"}}
            local func = function() return true end

            local accepted = 0
            for i = 1, 10 do
                local ok = bp_manager:add_entry(conf, i)
                if not ok then
                    ok = bp_manager:add_entry_to_new_processor(conf, i, ctx, func)
                end
                if ok then
                    accepted = accepted + 1
                end
            end
            ngx.say("accepted: ", accepted)
        }
    }
--- request
GET /t
--- response_body
accepted: 4
--- error_log
max_pending_entries: 3



=== TEST 3: discarding is reported at most once per second, with a running count
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugin")
            plugin.plugin_metadatas = {
                get = function(self, name)
                    return {value = {max_pending_entries = 1}}
                end
            }

            local bp_manager_mod = require("apisix.utils.batch-processor-manager")
            local bp_manager = bp_manager_mod.new("test logger", "test-logger")
            local conf = {
                name = "test logger",
                batch_max_size = 10000000,
                inactive_timeout = 300,
                buffer_duration = 300,
                max_retry_count = 0,
                retry_delay = 1,
            }
            local ctx = {var = {route_id = "1", server_addr = "127.0.0.1"}}
            local func = function() return true end

            for i = 1, 100 do
                local ok = bp_manager:add_entry(conf, i)
                if not ok then
                    bp_manager:add_entry_to_new_processor(conf, i, ctx, func)
                end
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- grep_error_log eval
qr/max pending entries limit exceeded/
--- grep_error_log_out
max pending entries limit exceeded



=== TEST 4: every batch-processor based logger exposes max_pending_entries
--- config
    location /t {
        content_by_lua_block {
            local loggers = {
                "clickhouse-logger", "datadog", "elasticsearch-logger",
                "google-cloud-logging", "http-logger", "kafka-logger", "lago",
                "loggly", "loki-logger", "rocketmq-logger", "skywalking-logger",
                "sls-logger", "splunk-hec-logging", "syslog", "tcp-logger",
                "tencent-cloud-cls", "udp-logger",
            }
            for _, name in ipairs(loggers) do
                local mod = require("apisix.plugins." .. name)
                local schema = mod.metadata_schema
                local prop = schema and schema.properties
                             and schema.properties.max_pending_entries
                if not prop or not prop.default then
                    ngx.say(name, ": missing max_pending_entries default")
                end
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
