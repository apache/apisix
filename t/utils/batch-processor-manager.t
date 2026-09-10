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

            -- a discard is reported as handled, so the caller only falls through
            -- while there is still no processor to push to
            local fell_through = 0
            for i = 1, 20000 do
                if not bp_manager:add_entry(conf, i) then
                    fell_through = fell_through + 1
                    bp_manager:add_entry_to_new_processor(conf, i, ctx, func)
                end
            end
            ngx.say("pushed: ", bp_manager.total_pushed_entries)
            ngx.say("fell through: ", fell_through)
        }
    }
--- request
GET /t
--- response_body
pushed: 8192
fell through: 1
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

            local fell_through = 0
            for i = 1, 10 do
                if not bp_manager:add_entry(conf, i) then
                    fell_through = fell_through + 1
                    bp_manager:add_entry_to_new_processor(conf, i, ctx, func)
                end
            end
            ngx.say("pushed: ", bp_manager.total_pushed_entries)
            ngx.say("fell through: ", fell_through)
        }
    }
--- request
GET /t
--- response_body
pushed: 3
fell through: 1
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

            local push = function(n)
                for i = 1, n do
                    local ok = bp_manager:add_entry(conf, i)
                    if not ok then
                        bp_manager:add_entry_to_new_processor(conf, i, ctx, func)
                    end
                end
            end

            -- one entry fits, the other 99 are discarded but reported only once
            push(100)
            -- past the interval the next discard reports, and its count covers
            -- every entry discarded since the previous report
            ngx.sleep(1.1)
            push(5)
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- grep_error_log eval
qr/discarded_entries: \d+/
--- grep_error_log_out
discarded_entries: 1
discarded_entries: 99



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
            table.insert(loggers, "stream syslog")
            for _, name in ipairs(loggers) do
                local mod = require(name == "stream syslog"
                                    and "apisix.stream.plugins.syslog"
                                    or "apisix.plugins." .. name)
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



=== TEST 5: every logger's batch processor reads its own plugin's metadata
--- config
    location /t {
        content_by_lua_block {
            -- a manager built without its plugin name looks metadata up under the
            -- batch processor's display name, silently ignoring any override
            local loggers = {
                "clickhouse-logger", "datadog", "elasticsearch-logger",
                "google-cloud-logging", "http-logger", "kafka-logger", "lago",
                "loggly", "loki-logger", "rocketmq-logger", "skywalking-logger",
                "sls-logger", "splunk-hec-logging", "syslog", "tcp-logger",
                "tencent-cloud-cls", "udp-logger",
            }
            -- the stream plugin and the shared syslog module both log as "syslog"
            local modules = {["apisix.stream.plugins.syslog"] = "syslog"}
            local order = {}
            for _, name in ipairs(loggers) do
                modules["apisix.plugins." .. name] = name
                table.insert(order, "apisix.plugins." .. name)
            end
            table.insert(order, "apisix.stream.plugins.syslog")

            local bp_manager_mod = require("apisix.utils.batch-processor-manager")
            local orig_new = bp_manager_mod.new
            local created
            local checked = 0

            for _, path in ipairs(order) do
                -- syslog keeps its batch processor in a module shared with the
                -- stream plugin; reload it alongside so whichever plugin is under
                -- test is the one that builds it
                package.loaded["apisix.plugins.syslog.init"] = nil
                package.loaded[path] = nil

                created = {}
                bp_manager_mod.new = function(name, plugin_name)
                    local manager = orig_new(name, plugin_name)
                    table.insert(created, manager)
                    return manager
                end
                require(path)
                bp_manager_mod.new = orig_new

                if #created == 0 then
                    ngx.say(path, " built no batch processor")
                end
                for _, manager in ipairs(created) do
                    checked = checked + 1
                    if manager.plugin_name ~= modules[path] then
                        ngx.say(path, ": batch processor '", manager.name,
                                "' reads the metadata of '", manager.plugin_name,
                                "', expected '", modules[path], "'")
                    end
                end
            end
            ngx.say("checked ", checked, " batch processors")
        }
    }
--- request
GET /t
--- response_body
checked 20 batch processors



=== TEST 6: max_pending_entries is validated through each plugin's metadata schema
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local loggers = {
                "clickhouse-logger", "datadog", "elasticsearch-logger",
                "google-cloud-logging", "http-logger", "kafka-logger", "lago",
                "loggly", "loki-logger", "rocketmq-logger", "skywalking-logger",
                "sls-logger", "splunk-hec-logging", "syslog", "tcp-logger",
                "tencent-cloud-cls", "udp-logger",
            }
            table.insert(loggers, "stream syslog")
            for _, name in ipairs(loggers) do
                local mod = require(name == "stream syslog"
                                    and "apisix.stream.plugins.syslog"
                                    or "apisix.plugins." .. name)
                local ok, err = mod.check_schema({max_pending_entries = 100},
                                                 core.schema.TYPE_METADATA)
                if not ok then
                    ngx.say(name, " rejected a valid override: ", err)
                end
                if mod.check_schema({max_pending_entries = 0},
                                    core.schema.TYPE_METADATA) then
                    ngx.say(name, " accepted max_pending_entries = 0")
                end
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done



=== TEST 7: the limit reaches a plugin that never carried it before
--- extra_yaml_config
plugins:
  - sls-logger
--- config
location /t {
    content_by_lua_block {
        local http = require "resty.http"
        local httpc = http.new()
        local t = require("lib.test_admin").test

        local code, body = t('/apisix/admin/plugin_metadata/sls-logger',
                             ngx.HTTP_PUT, {max_pending_entries = 1})
        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end

        -- nothing listens on the log port, and retries keep the first entry
        -- pending, so everything after it is over the limit
        code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, {
            plugins = {
                ["sls-logger"] = {
                    host = "127.0.0.1",
                    port = 1234,
                    project = "test-project",
                    logstore = "test-logstore",
                    access_key_id = "test-key-id",
                    access_key_secret = "test-key-secret",
                    batch_max_size = 1,
                    max_retry_count = 10,
                    retry_delay = 1,
                    timeout = 1,
                },
            },
            upstream = {
                nodes = {["127.0.0.1:1980"] = 1},
                type = "roundrobin",
            },
            uri = "/hello",
        })
        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end

        local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
        for i = 1, 3 do
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.say("request ", i, " failed: ", err)
                return
            end
            if res.status ~= 200 then
                ngx.say("request ", i, " returned ", res.status)
                return
            end
        end
        ngx.sleep(1)
        ngx.say("passed")
    }
}
--- request
GET /t
--- response_body
passed
--- error_log
max pending entries limit exceeded. discarding entry
--- timeout: 5
