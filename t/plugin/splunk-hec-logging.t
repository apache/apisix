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



=== TEST 6: bad custom log format
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/splunk-hec-logging',
                 ngx.HTTP_PUT,
                 [[{
                        "log_format": "'$host' '$time_iso8601'"
                 }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.print(body)
                return
            end
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"invalid configuration: property \"log_format\" validation failed: wrong type: expected object, got string"}



=== TEST 7: set route to test custom log format
--- config
    location /t {
        content_by_lua_block {
            local config = {
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
                            uri = "http://127.0.0.1:1980/splunk_hec_logging",
                            token = "BD274822-96AA-4DA6-90EC-18940FB2414C"
                        },
                        batch_max_size = 1,
                        inactive_timeout = 1
                    }
                }
            }
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, config)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/plugin_metadata/splunk-hec-logging',
                 ngx.HTTP_PUT,
                 [[{
                        "log_format": {
                            "host": "$host",
                            "@timestamp": "$time_iso8601",
                            "client_ip": "$remote_addr"
                        }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 8: hit
--- extra_init_by_lua
    local core = require("apisix.core")
    local decode = require("toolkit.json").decode
    local up = require("lib.server")
    up.splunk_hec_logging = function()
        ngx.log(ngx.WARN, "the mock backend is hit")

        ngx.req.read_body()
        local data = ngx.req.get_body_data()
        ngx.log(ngx.WARN, data)
        data = decode(data)
        assert(data[1].event.client_ip == "127.0.0.1")
        assert(data[1].source == "apache-apisix-splunk-hec-logging")
        assert(data[1].host == core.utils.gethostname())
        ngx.say('{}')
    end
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- error_log
the mock backend is hit
--- no_error_log
[error]



=== TEST 9: set route to test custom log format in route
--- config
    location /t {
        content_by_lua_block {
            local config = {
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
                            uri = "http://127.0.0.1:1980/splunk_hec_logging",
                            token = "BD274822-96AA-4DA6-90EC-18940FB2414C"
                        },
                        log_format = {
                            host = "$host",
                            ["@timestamp"] = "$time_iso8601",
                            vip = "$remote_addr"
                        },
                        batch_max_size = 1,
                        inactive_timeout = 1
                    }
                }
            }
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, config)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 10: hit
--- extra_init_by_lua
    local core = require("apisix.core")
    local decode = require("toolkit.json").decode
    local up = require("lib.server")
    up.splunk_hec_logging = function()
        ngx.log(ngx.WARN, "the mock backend is hit")

        ngx.req.read_body()
        local data = ngx.req.get_body_data()
        ngx.log(ngx.WARN, data)
        data = decode(data)
        assert(data[1].event.vip == "127.0.0.1")
        assert(data[1].source == "apache-apisix-splunk-hec-logging")
        assert(data[1].host == core.utils.gethostname())
        ngx.say('{}')
    end
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- error_log
the mock backend is hit
--- no_error_log
[error]
