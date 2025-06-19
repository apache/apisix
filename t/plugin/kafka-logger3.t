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

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: should drop entries
--- extra_yaml_config
plugins:
  - kafka-logger
--- config
location /t {
    content_by_lua_block {
        local http = require "resty.http"
        local httpc = http.new()
        local data = {
            {
                input = {
                    plugins = {
                        ["kafka-logger"] = {
                            broker_list = {
                                ["127.0.0.1"] = 1234
                            },
                            kafka_topic = "test2",
                            producer_type = "async",
                            timeout = 1,
                            batch_max_size = 1,
                            required_acks = 1,
                            meta_format = "origin",
                            max_retry_count = 1000,
                        }
                    },
                    upstream = {
                        nodes = {
                            ["127.0.0.1:1980"] = 1
                        },
                        type = "roundrobin"
                    },
                    uri = "/hello",
                },
            },
        }

        local t = require("lib.test_admin").test

        -- Set plugin metadata
        local metadata = {
            log_format = {
                host = "$host",
                ["@timestamp"] = "$time_iso8601",
                client_ip = "$remote_addr"
            },
            max_pending_entries = -1, -- only for testing to trigger discard
        }
        local plugin_metadata = require("apisix.plugins.kafka-logger")
        plugin_metadata.metadata_schema.properties.max_pending_entries.minimum = -1
        local code, body = t('/apisix/admin/plugin_metadata/kafka-logger', ngx.HTTP_PUT, metadata)
        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end

        -- Create route
        local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, data[1].input)
        if code >= 300 then
            ngx.status = code
            ngx.say(body)
            return
        end

        local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
        local res, err = httpc:request_uri(uri, {
            method = "GET",
            headers = {
                ["Host"] = "example.com",
                ["User-Agent"] = "test-agent"
            },
            keepalive_timeout = 1,
            keepalive_pool = 10
        })
        if not res then
            ngx.log(ngx.ERR, "failed to request: ", err)
        end
    }
}
--- error_log
max pending entries limit exceeded. discarding entry
