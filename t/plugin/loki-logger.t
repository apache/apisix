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
                {endpoint_addrs = {"http://127.0.0.1:8199"}, headers = 1234},
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
property "headers" validation failed: wrong type: expected object, got number
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



=== TEST 15: setup route (test headers)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "loki-logger": {
                            "endpoint_addrs": ["http://127.0.0.1:1980"],
                            "endpoint_uri": "/log_request",
                            "headers": {"Authorization": "test1234"},
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



=== TEST 16: hit route (test headers)
--- request
GET /hello
--- response_body
hello world
--- error_log
go(): authorization: test1234



=== TEST 17: setup route with a per-request variable label (same conf for all requests)
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
                                "service": "$http_x_service_name"
                            },
                            "batch_max_size": 2
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



=== TEST 18: two requests with different label values share one worker and must not leak
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local cjson = require("cjson")

            -- all requests hit the same worker (worker_processes 1), so a buggy
            -- shared-conf / single-stream batch would freeze the first label and
            -- stamp every line with it. the last request omits x-service-name
            -- (boundary case): it must not inherit a prior request's label
            local req_headers = {
                { ["x-service-name"] = "svc-alpha" },
                { ["x-service-name"] = "svc-beta" },
                {},
            }
            for _, headers in ipairs(req_headers) do
                local httpc = http.new()
                local res, err = httpc:request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/hello",
                    { headers = headers })
                assert(res, "request failed: " .. (err or ""))
                assert(res.status == 200, "unexpected status: " .. res.status)
            end

            -- wait for the batch flush timer and Loki ingestion
            ngx.sleep(2)

            local loki = require("lib.grafana_loki")
            local now = ngx.now() * 1000
            local from = tostring(now - 10000) .. "000000"
            local to = tostring(now) .. "000000"

            for _, svc in ipairs({"svc-alpha", "svc-beta"}) do
                local data, err = loki.fetch_logs_from_loki(from, to,
                    { query = [[{service="]] .. svc .. [["} | json]] })

                assert(err == nil, "fetch logs error: " .. (err or ""))
                assert(data.status == "success",
                       "loki response error: " .. cjson.encode(data))
                assert(#data.data.result == 1,
                       "expected exactly one stream for service=" .. svc .. ": "
                       .. cjson.encode(data))

                local entry = data.data.result[1]
                assert(entry.stream.service == svc,
                       "expected stream service=" .. svc .. ": " .. cjson.encode(entry))
                assert(entry.stream.request_headers_x_service_name == svc,
                       "log line under service=" .. svc ..
                       " belongs to another request: " .. cjson.encode(entry))
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 19: setup route (log_format_extra enriches default via plugin metadata)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- additive log format: keep the rich default and add the pre-DNS
            -- upstream host on top
            local code, body = t('/apisix/admin/plugin_metadata/loki-logger',
                ngx.HTTP_PUT,
                [[{
                    "log_format_extra": {
                        "upstream_host": "$upstream_unresolved_host"
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "loki-logger": {
                            "endpoint_addrs": ["http://127.0.0.1:3100"],
                            "tenant_id": "tenant_1",
                            "log_labels": {
                                "enrich_label": "enrich_value"
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



=== TEST 20: hit route
--- request
GET /hello
--- response_body
hello world



=== TEST 21: check loki log (default fields kept + extra field added)
--- config
    location /t {
        content_by_lua_block {
            local cjson = require("cjson")
            local now = ngx.now() * 1000
            local data, err = require("lib.grafana_loki").fetch_logs_from_loki(
                tostring(now - 3000) .. "000000", -- from
                tostring(now) .. "000000",        -- to
                { query = [[{enrich_label="enrich_value"} | json]] }
            )

            assert(err == nil, "fetch logs error: " .. (err or ""))
            assert(data.status == "success", "loki response error: " .. cjson.encode(data))
            assert(#data.data.result > 0, "loki log empty: " .. cjson.encode(data))

            local entry = data.data.result[1]
            -- the extra field is added
            assert(entry.stream.upstream_host == "127.0.0.1",
                  "expected extra field upstream_host: " .. cjson.encode(entry))
            -- the rich default fields are still present
            assert(entry.stream.route_id == "1",
                  "expected default field route_id: " .. cjson.encode(entry))
            assert(entry.stream.request_method == "GET",
                  "expected default field request_method: " .. cjson.encode(entry))
        }
    }
--- error_code: 200
