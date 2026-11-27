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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: get_log_entry returns nil when get_full_log returns nil with log_format_extra and llm fields
--- config
    location /t {
        content_by_lua_block {
            local log_util = require("apisix.utils.log-util")
            local plugin = require("apisix.plugin")
            local orig_get_full_log = log_util.get_full_log
            local orig_plugin_metadata = plugin.plugin_metadata

            local ok, err = pcall(function()
                log_util.inject_get_full_log(function()
                    return nil
                end)

                local ctx = {
                    var = {
                        host = "localhost",
                        request_uri = "/t",
                    },
                    llm_summary = { model = "test" },
                    llm_request = { messages = {} },
                    llm_response_text = "ok",
                }

                -- conf.log_format_extra + ctx.llm_*
                local entry, customized, extra = log_util.get_log_entry("http-logger", {
                    include_req_body = true,
                    log_format_extra = { custom = "$host" },
                }, ctx)
                ngx.say("conf_extra: ", tostring(entry), " ", tostring(customized), " ", tostring(extra))

                -- plugin metadata log_format_extra + ctx.llm_*
                plugin.plugin_metadata = function()
                    return {
                        value = {
                            log_format_extra = { meta_custom = "$host" },
                        }
                    }
                end
                entry, customized, extra = log_util.get_log_entry("http-logger", {
                    include_req_body = true,
                }, ctx)
                ngx.say("meta_extra: ", tostring(entry), " ", tostring(customized), " ", tostring(extra))
            end)

            log_util.inject_get_full_log(orig_get_full_log)
            plugin.plugin_metadata = orig_plugin_metadata
            if not ok then
                ngx.say("error: ", err)
            end
        }
    }
--- response_body
conf_extra: nil nil nil
meta_extra: nil nil nil



=== TEST 2: get_log_entry returns nil when match excludes the request
--- config
    location /t {
        content_by_lua_block {
            local log_util = require("apisix.utils.log-util")
            local ctx = {
                var = {
                    arg_log = "no",
                    host = "localhost",
                },
                llm_summary = { model = "test" },
            }
            local conf = {
                match = {
                    { { "arg_log", "==", "yes" } },
                },
                log_format_extra = { custom = "$host" },
            }

            local entry, customized, extra = log_util.get_log_entry("http-logger", conf, ctx)
            ngx.say(tostring(entry), " ", tostring(customized), " ", tostring(extra))
        }
    }
--- response_body
nil nil nil



=== TEST 3: logger plugins skip nil entries without raising or pushing to batch processors
--- config
    location /t {
        content_by_lua_block {
            local bp_manager = require("apisix.utils.batch-processor-manager")
            local log_util = require("apisix.utils.log-util")
            local syslog_init = require("apisix.plugins.syslog.init")

            local orig_add_entry = bp_manager.add_entry
            local orig_add_new = bp_manager.add_entry_to_new_processor
            local orig_syslog_push = syslog_init.push_entry
            local orig_get_full_log = log_util.get_full_log

            local pushed = {}
            bp_manager.add_entry = function(self, conf, entry)
                pushed[#pushed + 1] = "add_entry:" .. tostring(self.plugin_name)
                return true
            end
            bp_manager.add_entry_to_new_processor = function(self, conf, entry, ctx, func)
                pushed[#pushed + 1] = "add_new:" .. tostring(self.plugin_name)
                return true
            end
            syslog_init.push_entry = function(conf, ctx, entry)
                pushed[#pushed + 1] = "syslog_push"
            end

            local cases = {
                {
                    name = "http-logger",
                    conf = { uri = "http://127.0.0.1:1980/log" },
                },
                {
                    name = "loki-logger",
                    conf = {
                        endpoint_addrs = { "http://127.0.0.1:3100" },
                        log_labels = { job = "apisix" },
                    },
                },
                {
                    name = "tencent-cloud-cls",
                    conf = {
                        cls_host = "127.0.0.1",
                        cls_topic = "topic",
                        secret_id = "id",
                        secret_key = "key",
                        global_tag = { env = "test" },
                    },
                },
                {
                    name = "google-cloud-logging",
                    conf = {
                        auth_config = {
                            client_email = "test@example.iam.gserviceaccount.com",
                            private_key = "key",
                            project_id = "proj",
                            token_uri = "http://127.0.0.1:1980/token",
                        },
                        resource = { type = "global" },
                        log_id = "test-log",
                    },
                },
                {
                    name = "splunk-hec-logging",
                    conf = {
                        endpoint = {
                            uri = "http://127.0.0.1:8088",
                            token = "tok",
                            timeout = 1,
                        },
                    },
                },
                {
                    name = "sls-logger",
                    conf = {
                        host = "127.0.0.1",
                        port = 10009,
                        project = "proj",
                        logstore = "store",
                        access_key_id = "id",
                        access_key_secret = "secret",
                    },
                },
                {
                    name = "loggly",
                    conf = {
                        customer_token = "tok",
                        severity = "info",
                    },
                },
                {
                    name = "syslog",
                    conf = {
                        host = "127.0.0.1",
                        port = 514,
                    },
                },
                {
                    name = "skywalking-logger",
                    conf = {
                        endpoint_addr = "http://127.0.0.1:12800",
                        service_name = "apisix",
                        service_instance_name = "inst",
                    },
                },
            }

            local function run_all(label, mode)
                local ctx = {
                    conf_type = "route",
                    conf_id = "1",
                    conf_version = "1",
                    cls_sample = true,
                    var = {
                        arg_log = "no",
                        host = "localhost",
                        pid = "1",
                        uri = "/t",
                        request_id = "req-1",
                    },
                }

                for _, c in ipairs(cases) do
                    local mod = require("apisix.plugins." .. c.name)
                    local conf = {}
                    for k, v in pairs(c.conf) do
                        conf[k] = v
                    end
                    if mode == "match" then
                        conf.match = {
                            { { "arg_log", "==", "yes" } },
                        }
                    else
                        conf.include_req_body = true
                    end

                    local ok, err = pcall(mod.log, conf, ctx)
                    if not ok then
                        ngx.say(label, " ", c.name, " raised: ", err)
                    end
                end
            end

            local ok, err = pcall(function()
                run_all("match", "match")

                log_util.inject_get_full_log(function()
                    return nil
                end)
                run_all("body_fail", "body_fail")
            end)

            log_util.inject_get_full_log(orig_get_full_log)
            bp_manager.add_entry = orig_add_entry
            bp_manager.add_entry_to_new_processor = orig_add_new
            syslog_init.push_entry = orig_syslog_push

            if not ok then
                ngx.say("unexpected error: ", err)
            end
            ngx.say("pushed_count: ", #pushed)
            for _, item in ipairs(pushed) do
                ngx.say("pushed: ", item)
            end
        }
    }
--- response_body
pushed_count: 0
--- no_error_log
[error]



=== TEST 4: route with http-logger and non-matching match does not fail log phase or send a log
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, {
                uri = "/hello",
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    }
                },
                plugins = {
                    ["http-logger"] = {
                        uri = "http://127.0.0.1:1980/log",
                        batch_max_size = 1,
                        match = {
                            { { "arg_log", "==", "yes" } },
                        },
                        log_format_extra = {
                            custom_host = "$host",
                        },
                    }
                }
            })
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local base = "http://127.0.0.1:" .. ngx.var.server_port
            local res, err = http.new():request_uri(base .. "/hello?log=no")
            if not res or res.status ~= 200 then
                ngx.say("non-matching request failed: ", err or res.status)
                return
            end
            res, err = http.new():request_uri(base .. "/hello?log=yes")
            if not res or res.status ~= 200 then
                ngx.say("matching request failed: ", err or res.status)
                return
            end
            ngx.sleep(1)
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
request log:
--- no_error_log
failed to run log_by_lua
--- grep_error_log eval
qr/request log:/
--- grep_error_log_out
request log:
--- timeout: 10
