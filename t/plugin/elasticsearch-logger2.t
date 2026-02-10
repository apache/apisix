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

log_level('debug');
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: should drop entries when max_pending_entries is exceededA
--- extra_yaml_config
plugins:
  - elasticsearch-logger
--- config
location /t {
    content_by_lua_block {
        local http = require "resty.http"
        local httpc = http.new()
        local data = {
            {
                input = {
                    plugins = {
                        ["elasticsearch-logger"] = {
                            endpoint_addr = "http://127.0.0.1:1234",
                            field = {
                                index = "services"
                            },
                            batch_max_size = 1,
                            timeout = 1,
                            max_retry_count = 10
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
            max_pending_entries = 1
        }

        local code, body = t('/apisix/admin/plugin_metadata/elasticsearch-logger', ngx.HTTP_PUT, metadata)
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
        httpc:request_uri(uri, {
            method = "GET",
            keepalive_timeout = 1,
            keepalive_pool = 1,
        })
        httpc:request_uri(uri, {
            method = "GET",
            keepalive_timeout = 1,
            keepalive_pool = 1,
        })
        httpc:request_uri(uri, {
            method = "GET",
            keepalive_timeout = 1,
            keepalive_pool = 1,
        })
        ngx.sleep(2)
    }
}
--- error_log
max pending entries limit exceeded. discarding entry
--- timeout: 5



=== TEST 2: set route with header auth
--- config
    location /t {
        content_by_lua_block {
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
                    ["elasticsearch-logger"] = {
                        endpoint_addr = "http://127.0.0.1:9201",
                        field = {
                            index = "services"
                        },
                        auth = {
                            header_name = "Authorization",
                            header_value = "Basic ZWxhc3RpYzoxMjM0NTY="
                        },
                        batch_max_size = 1,
                        inactive_timeout = 1
                    }
                }
            })

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 3: test route (auth success)
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- error_log
Batch Processor[elasticsearch-logger] successfully processed the entries
