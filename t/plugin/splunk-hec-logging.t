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

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: configuration verification
--- config
    location /t {
        content_by_lua_block {
            local ok, err
            local configs = {
                -- full configuration
                {
                    endpoint = {
                        uri = "http://127.0.0.1:18088/services/collector",
                        token = "BD274822-96AA-4DA6-90EC-18940FB2414C",
                        channel = "FE0ECFAD-13D5-401B-847D-77833BD77131",
                        timeout = 60
                    },
                    max_retry_count = 0,
                    retry_delay = 1,
                    buffer_duration = 60,
                    inactive_timeout = 2,
                    batch_max_size = 10,
                },
                -- minimize configuration
                {
                    endpoint = {
                        uri = "http://127.0.0.1:18088/services/collector",
                        token = "BD274822-96AA-4DA6-90EC-18940FB2414C",
                    }
                },
                -- property "uri" is required
                {
                    endpoint = {
                        token = "BD274822-96AA-4DA6-90EC-18940FB2414C",
                    }
                },
                -- property "token" is required
                {
                    endpoint = {
                        uri = "http://127.0.0.1:18088/services/collector",
                    }
                },
                -- property "uri" validation failed
                {
                    endpoint = {
                        uri = "127.0.0.1:18088/services/collector",
                        token = "BD274822-96AA-4DA6-90EC-18940FB2414C",
                    }
                }
            }

            local plugin = require("apisix.plugins.splunk-hec-logging")
            for i = 1, #configs do
                ok, err = plugin.check_schema(configs[i])
                if err then
                    ngx.say(err)
                else
                    ngx.say("passed")
                end
            end
        }
    }
--- response_body_like
passed
passed
property "endpoint" validation failed: property "uri" is required
property "endpoint" validation failed: property "token" is required
property "endpoint" validation failed: property "uri" validation failed.*



=== TEST 2: set route (failed auth)
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
                    ["splunk-hec-logging"] = {
                        endpoint = {
                            uri = "http://127.0.0.1:18088/services/collector",
                            token = "BD274822-96AA-4DA6-90EC-18940FB24444"
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



=== TEST 3: test route (failed auth)
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- error_log
Batch Processor[splunk-hec-logging] failed to process entries: failed to send splunk, Invalid token
Batch Processor[splunk-hec-logging] exceeded the max_retry_count



=== TEST 4: set route (success write)
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
                    ["splunk-hec-logging"] = {
                        endpoint = {
                            uri = "http://127.0.0.1:18088/services/collector",
                            token = "BD274822-96AA-4DA6-90EC-18940FB2414C"
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



=== TEST 5: test route (success write)
--- request
GET /hello
--- wait: 2
--- response_body
hello world
