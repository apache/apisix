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

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local ok, err
            local configs = {
                -- full configuration
                {
                    endpoint_addr = "http://127.0.0.1:9200",
                    field = {
                        index = "services",
                        type = "collector"
                    },
                    auth = {
                        username = "elastic",
                        password = "123456"
                    },
                    ssl_verify = false,
                    timeout = 60,
                    max_retry_count = 0,
                    retry_delay = 1,
                    buffer_duration = 60,
                    inactive_timeout = 2,
                    batch_max_size = 10,
                },
                -- minimize configuration
                {
                    endpoint_addr = "http://127.0.0.1:9200",
                    field = {
                        index = "services"
                    }
                },
                -- property "endpoint_addr" is required
                {
                    field = {
                        index = "services"
                    }
                },
                -- property "field" is required
                {
                    endpoint_addr = "http://127.0.0.1:9200",
                },
                -- property "index" is required
                {
                    endpoint_addr = "http://127.0.0.1:9200",
                    field = {}
                },
                -- property "endpoint" must not end with "/"
                {
                    endpoint_addr = "http://127.0.0.1:9200/",
                    field = {
                        index = "services"
                    }
                }
            }

            local plugin = require("apisix.plugins.elasticsearch-logger")
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
property "endpoint_addr" is required
property "field" is required
property "field" validation failed: property "index" is required
property "endpoint_addr" validation failed: failed to match pattern "\[\^/\]\$" with "http://127.0.0.1:9200/"



=== TEST 2: set route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/elasticsearch-logger',
                               ngx.HTTP_DELETE)

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
                        endpoint_addr = "http://127.0.0.1:9200",
                        field = {
                            index = "services"
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



=== TEST 3: test route (success write)
--- extra_init_by_lua
    local core = require("apisix.core")
    local http = require("resty.http")
    local ngx_re = require("ngx.re")
    local log_util = require("apisix.utils.log-util")
    log_util.get_full_log = function(ngx, conf)
        return {
            test = "test"
        }
    end

    http.request_uri = function(self, uri, params)
        if not params.body or type(params.body) ~= "string" then
            return nil, "invalid params body"
        end

        local arr = ngx_re.split(params.body, "\n")
        if not arr or #arr ~= 2 then
            return nil, "invalid params body"
        end

        local entry = core.json.decode(arr[2])
        local origin_entry = log_util.get_full_log(ngx, {})
        for k, v in pairs(origin_entry) do
            local vv = entry[k]
            if not vv or vv ~= v then
                return nil, "invalid params body"
            end
        end

        core.log.error("check elasticsearch full log body success")
        return {
            status = 200,
            body = "success"
        }, nil
    end
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- error_log
check elasticsearch full log body success



=== TEST 4: set route (auth)
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
                            username = "elastic",
                            password = "123456"
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



=== TEST 5: test route (auth success)
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- error_log
Batch Processor[elasticsearch-logger] successfully processed the entries



=== TEST 6: set route (no auth)
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



=== TEST 7: test route (no auth, failed)
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- error_log
Batch Processor[elasticsearch-logger] failed to process entries: elasticsearch server returned status: 401
"reason":"missing authentication credentials for REST request [/_bulk]"
Batch Processor[elasticsearch-logger] exceeded the max_retry_count



=== TEST 8: set route (error auth)
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
                            username = "elastic",
                            password = "111111"
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



=== TEST 9: test route (error auth failed)
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- error_log
Batch Processor[elasticsearch-logger] failed to process entries
Batch Processor[elasticsearch-logger] exceeded the max_retry_count



=== TEST 10: add plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/elasticsearch-logger',
                ngx.HTTP_PUT, [[{
                    "log_format": {
                        "custom_host": "$host",
                        "custom_timestamp": "$time_iso8601",
                        "custom_client_ip": "$remote_addr"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)

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
--- response_body_like
passed
passed



=== TEST 11: hit route and check custom elasticsearch logger
--- extra_init_by_lua
    local core = require("apisix.core")
    local http = require("resty.http")
    local ngx_re = require("ngx.re")
    local log_util = require("apisix.utils.log-util")
    log_util.get_custom_format_log = function(ctx, format)
        return {
            test = "test"
        }
    end

    http.request_uri = function(self, uri, params)
        if not params.body or type(params.body) ~= "string" then
            return nil, "invalid params body"
        end

        local arr = ngx_re.split(params.body, "\n")
        if not arr or #arr ~= 2 then
            return nil, "invalid params body"
        end

        local entry = core.json.decode(arr[2])
        local origin_entry = log_util.get_custom_format_log(nil, nil)
        for k, v in pairs(origin_entry) do
            local vv = entry[k]
            if not vv or vv ~= v then
                return nil, "invalid params body"
            end
        end

        core.log.error("check elasticsearch custom body success")
        return {
            status = 200,
            body = "success"
        }, nil
    end
--- request
GET /hello
--- response_body
hello world
--- wait: 2
--- error_log
check elasticsearch custom body success
