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

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local test_cases = {
                {endpoint_addrs = {"http://127.0.0.1:8199"}},
                {endpoint_addrs = "http://127.0.0.1:8199"},
                {endpoint_addrs = {}},
                {},
                {endpoint_addrs = {"http://127.0.0.1:8199"}, endpoint_uri = "/loki/api/v1/push"},
                {endpoint_addrs = {"http://127.0.0.1:8199"}, endpoint_uri = 1234},
                {endpoint_addrs = {"http://127.0.0.1:8199"}, tenant_id = 1234},
                {endpoint_addrs = {"http://127.0.0.1:8199"}, request_headers = 1234},
                {endpoint_addrs = {"http://127.0.0.1:8199"}, log_labels = "1234"},
                {endpoint_addrs = {"http://127.0.0.1:8199"}, log_labels = {job = "apisix6"}},
            }
            local plugin = require("apisix.plugins.loki-logger")

            for _, case in ipairs(test_cases) do
                local ok, err = plugin.check_schema(case)
                ngx.say(ok and "done" or err)
            end
        }
    }
--- response_body
done
property "endpoint_addrs" validation failed: wrong type: expected array, got string
property "endpoint_addrs" validation failed: expect array to have at least 1 items
property "endpoint_addrs" is required
done
property "endpoint_uri" validation failed: wrong type: expected string, got number
property "tenant_id" validation failed: wrong type: expected string, got number
property "request_headers" validation failed: wrong type: expected object, got number
property "log_labels" validation failed: wrong type: expected object, got string
done



=== TEST 2: setup route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "loki-logger": {
                            "endpoint_addrs": ["http://127.0.0.1:3100"],
                            "tenant_id": "tenant_1",
                            "batch_max_size": 1
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 3: hit route
--- request
GET /hello
--- more_headers
test-header: only-for-test#1
--- response_body
hello world



=== TEST 4: check loki log
--- config
    location /t {
        content_by_lua_block {
            local cjson = require("cjson")
            local now = ngx.now() * 1000
            local data, err = require("lib.grafana_loki").fetch_logs_from_loki(
                tostring(now - 3000) .. "000000", -- from
                tostring(now) .. "000000"         -- to
            )

            assert(err == nil, "fetch logs error: " .. (err or ""))
            assert(data.status == "success", "loki response error: " .. cjson.encode(data))
            assert(#data.data.result > 0, "loki log empty: " .. cjson.encode(data))

            local entry = data.data.result[1]
            assert(entry.stream.request_headers_test_header == "only-for-test#1",
                  "expected field request_headers_test_header value: " .. cjson.encode(entry))
        }
    }
--- error_code: 200



=== TEST 5: setup route (with log_labels)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "loki-logger": {
                            "endpoint_addrs": ["http://127.0.0.1:3100"],
                            "tenant_id": "tenant_1",
                            "log_labels": {
                                "custom_label": "custom_label_value"
                            },
                            "batch_max_size": 1
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 6: hit route
--- request
GET /hello
--- more_headers
test-header: only-for-test#2
--- response_body
hello world



=== TEST 7: check loki log (with custom_label)
--- config
    location /t {
        content_by_lua_block {
            local cjson = require("cjson")
            local now = ngx.now() * 1000
            local data, err = require("lib.grafana_loki").fetch_logs_from_loki(
                tostring(now - 3000) .. "000000", -- from
                tostring(now) .. "000000",        -- to
                { query = [[{custom_label="custom_label_value"} | json]] }
            )

            assert(err == nil, "fetch logs error: " .. (err or ""))
            assert(data.status == "success", "loki response error: " .. cjson.encode(data))
            assert(#data.data.result > 0, "loki log empty: " .. cjson.encode(data))

            local entry = data.data.result[1]
            assert(entry.stream.request_headers_test_header == "only-for-test#2",
                  "expected field request_headers_test_header value: " .. cjson.encode(entry))
        }
    }
--- error_code: 200



=== TEST 8: setup route (with tenant_id)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "loki-logger": {
                            "endpoint_addrs": ["http://127.0.0.1:3100"],
                            "tenant_id": "tenant_2",
                            "batch_max_size": 1
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 9: hit route
--- request
GET /hello
--- more_headers
test-header: only-for-test#3
--- response_body
hello world



=== TEST 10: check loki log (with tenant_id tenant_1)
--- config
    location /t {
        content_by_lua_block {
            local cjson = require("cjson")
            local now = ngx.now() * 1000
            local data, err = require("lib.grafana_loki").fetch_logs_from_loki(
                tostring(now - 10000) .. "000000", -- from
                tostring(now) .. "000000"          -- to
            )

            assert(err == nil, "fetch logs error: " .. (err or ""))
            assert(data.status == "success", "loki response error: " .. cjson.encode(data))
            assert(#data.data.result > 0, "loki log empty: " .. cjson.encode(data))

            local entry = data.data.result[1]
            assert(entry.stream.request_headers_test_header ~= "only-for-test#3",
                  "expected field request_headers_test_header value: " .. cjson.encode(entry))
        }
    }
--- error_code: 200



=== TEST 11: check loki log (with tenant_id tenant_2)
--- config
    location /t {
        content_by_lua_block {
            local cjson = require("cjson")
            local now = ngx.now() * 1000
            local data, err = require("lib.grafana_loki").fetch_logs_from_loki(
                tostring(now - 3000) .. "000000", -- from
                tostring(now) .. "000000",        -- to
                { headers = {
                        ["X-Scope-OrgID"] = "tenant_2"
                } }
            )

            assert(err == nil, "fetch logs error: " .. (err or ""))
            assert(data.status == "success", "loki response error: " .. cjson.encode(data))
            assert(#data.data.result > 0, "loki log empty: " .. cjson.encode(data))

            local entry = data.data.result[1]
            assert(entry.stream.request_headers_test_header == "only-for-test#3",
                  "expected field request_headers_test_header value: " .. cjson.encode(entry))
        }
    }
--- error_code: 200



=== TEST 12: setup route (with log_labels as variables)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "loki-logger": {
                            "endpoint_addrs": ["http://127.0.0.1:3100"],
                            "tenant_id": "tenant_1",
                            "log_labels": {
                                "custom_label": "$remote_addr"
                            },
                            "batch_max_size": 1
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 13: hit route
--- request
GET /hello
--- response_body
hello world



=== TEST 14: check loki log (with custom_label)
--- config
    location /t {
        content_by_lua_block {
            local cjson = require("cjson")
            local now = ngx.now() * 1000
            local data, err = require("lib.grafana_loki").fetch_logs_from_loki(
                tostring(now - 3000) .. "000000", -- from
                tostring(now) .. "000000",        -- to
                { query = [[{custom_label="127.0.0.1"} | json]] }
            )

            assert(err == nil, "fetch logs error: " .. (err or ""))
            assert(data.status == "success", "loki response error: " .. cjson.encode(data))
            assert(#data.data.result > 0, "loki log empty: " .. cjson.encode(data))
        }
    }
--- error_code: 200
