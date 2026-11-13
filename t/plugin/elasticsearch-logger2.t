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

add_block_preprocessor(sub {
    my ($block) = @_;

    # The plugin no longer logs uri/body; reproduce the observability the
    # tests rely on by wrapping the HTTP client from a test-only hook. This
    # wraps whatever request_uri is in place (the real one or a per-block
    # mock), so it composes with the existing mocks.
    my $log_wrap = <<_EOC_;
    do
        local http = require("resty.http")
        local core = require("apisix.core")
        local _orig_request_uri = http.request_uri
        http.request_uri = function(self, uri, params)
            core.log.info("uri: ", uri, ", body: ", params and params.body or "")
            return _orig_request_uri(self, uri, params)
        end
    end
_EOC_
    $block->set_value("extra_init_by_lua",
                      ($block->extra_init_by_lua // '') . $log_wrap);
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
        local code, body = t('/apisix/admin/plugin_metadata/elasticsearch-logger', ngx.HTTP_DELETE)
        if not code or code >= 300 then
            ngx.status = code or ngx.HTTP_INTERNAL_SERVER_ERROR
            ngx.say(body)
            return
        end
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
                        headers = {
                            Authorization = "Basic ZWxhc3RpYzoxMjM0NTY="
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



=== TEST 4: resolve_index_vars unit test
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.elasticsearch-logger")
            local configs = {
                ["%Y"] = "^\\d{4}$",
                ["%m"] = "^\\d{2}$",
                ["%d"] = "^\\d{2}$",
                ["%Y.%m.%d"] = "^\\d{4}\\.\\d{2}\\.\\d{2}$",
            }

            for format, regex in pairs(configs) do
                local new = plugin._resolve_index_vars("prefix{" .. format .. "}suffix")
                local ok = ngx.re.match(new, "^prefix" .. regex:sub(2, -2) .. "suffix$")
                if not ok then
                   ngx.say("error: " .. new)
                   return
                end
            end
            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 5: test date variable in index
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
                            index = "services-{%Y.%m.%d}"
                        },
                        auth = {
                            username = "elastic",
                            password = "123456"
                        },
                        batch_max_size = 1,
                        inactive_timeout = 1,
                    }
                }
            })

            if code >= 300 then
                ngx.status = code
            end

            local code, _, body = t("/hello")
        }
    }
--- error_log eval
qr/body: \{"index":\{"_index":"services-\d\d\d\d\.\d\d\.\d\d"\}\}/



=== TEST 6: test APISIX variable in index
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
                            index = "services-$host"
                        },
                        auth = {
                            username = "elastic",
                            password = "123456"
                        },
                        batch_max_size = 1,
                        inactive_timeout = 1,
                    }
                }
            })

            if code >= 300 then
                ngx.status = code
            end

            local code, _, body = t("/hello")
        }
    }
--- error_log eval
qr/body: \{"index":\{"_index":"services-127.0.0.1"\}\}/



=== TEST 7: test both APISIX variable and date variable in index
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
                            index = "services-$host-{%Y.%m.%d}"
                        },
                        auth = {
                            username = "elastic",
                            password = "123456"
                        },
                        batch_max_size = 1,
                        inactive_timeout = 1,
                    }
                }
            })

            if code >= 300 then
                ngx.status = code
            end

            local code, _, body = t("/hello")
        }
    }
--- error_log eval
qr/body: \{"index":\{"_index":"services-127.0.0.1-\d\d\d\d\.\d\d\.\d\d"\}\}/



=== TEST 8: dynamic index template should not be mutated across requests
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
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
                            index = "services-$arg_id-{%Y.%m.%d}"
                        },
                        auth = {
                            username = "elastic",
                            password = "123456"
                        },
                        batch_max_size = 1,
                        inactive_timeout = 1,
                    }
                }
            })

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local port = ngx.var.server_port
            local res, err = httpc:request_uri("http://127.0.0.1:" .. port .. "/hello?id=first", {method = "GET"})
            if not res then
                ngx.say("request 1 failed: ", err)
                return
            end
            res, err = httpc:request_uri("http://127.0.0.1:" .. port .. "/hello?id=second", {method = "GET"})
            if not res then
                ngx.say("request 2 failed: ", err)
                return
            end
            ngx.sleep(2)
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log eval
[qr/body: \{"index":\{"_index":"services-first-\d\d\d\d\.\d\d\.\d\d"\}\}/, qr/body: \{"index":\{"_index":"services-second-\d\d\d\d\.\d\d\.\d\d"\}\}/]
--- timeout: 5



=== TEST 9: ${xx} variable syntax should not trigger time replacement
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
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
                            index = "services-${arg_id}-{%Y.%m.%d}"
                        },
                        auth = {
                            username = "elastic",
                            password = "123456"
                        },
                        batch_max_size = 1,
                        inactive_timeout = 1,
                    }
                }
            })

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local port = ngx.var.server_port
            local res, err = httpc:request_uri("http://127.0.0.1:" .. port .. "/hello?id=myservice", {method = "GET"})
            if not res then
                ngx.say("request failed: ", err)
                return
            end
            ngx.sleep(2)
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log eval
qr/body: \{"index":\{"_index":"services-myservice-\d\d\d\d\.\d\d\.\d\d"\}\}/
--- no_error_log
failed to parse time format
--- timeout: 5



=== TEST 10: non-string time format (os.date "*t" returns a table) falls back
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.elasticsearch-logger")
            -- "*t"/"!*t" make os.date return a table instead of a string;
            -- replace_time must reject it rather than stringify a garbage index.
            for _, fmt in ipairs({"*t", "!*t"}) do
                local new = plugin._resolve_index_vars("prefix{" .. fmt .. "}suffix")
                if new ~= "prefixsuffix" then
                    ngx.say("error: " .. new)
                    return
                end
            end
            ngx.say("ok")
        }
    }
--- response_body
ok
--- error_log
failed to parse time format



=== TEST 11: two routes whose clusters run the same Elasticsearch major version
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local function put_route(id, uri, es_conf)
                return t('/apisix/admin/routes/' .. id, ngx.HTTP_PUT, {
                    uri = uri,
                    upstream = {
                        type = "roundrobin",
                        nodes = {
                            ["127.0.0.1:1980"] = 1
                        }
                    },
                    plugins = {
                        ["elasticsearch-logger"] = es_conf
                    }
                })
            end

            -- both clusters are Elasticsearch 8, the second one with authentication
            local code, body = put_route(1, "/hello", {
                endpoint_addrs = {"http://127.0.0.1:9200"},
                field = {
                    index = "route-a-logs"
                },
                batch_max_size = 1,
                inactive_timeout = 1,
            })
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = put_route(2, "/hello1", {
                endpoint_addrs = {"http://127.0.0.1:9201"},
                field = {
                    index = "route-b-logs"
                },
                auth = {
                    username = "elastic",
                    password = "123456"
                },
                batch_max_size = 1,
                inactive_timeout = 1,
            })
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 12: each route sends its logs to its own cluster with its own credentials
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local json = require("toolkit.json")

            -- the routes only shared a processor when both clusters reported the
            -- same major version, so check that this still holds for the CI services
            local function major_version(uri, headers)
                local res, err = http.new():request_uri(uri, {headers = headers})
                if not res or res.status ~= 200 then
                    return nil, err or res.status
                end
                return json.decode(res.body).version.number:match("^(%d+)%.")
            end
            local version_a, err_a = major_version("http://127.0.0.1:9200")
            local version_b, err_b = major_version("http://127.0.0.1:9201", {
                Authorization = "Basic " .. ngx.encode_base64("elastic:123456")
            })
            if not version_a or version_a ~= version_b then
                ngx.say("the clusters do not run the same major version: ",
                        version_a or err_a, " and ", version_b or err_b)
                return
            end

            local base = "http://127.0.0.1:" .. ngx.var.server_port
            -- the first route's batch processor exists by the time the second logs
            for _, uri in ipairs({"/hello", "/hello1"}) do
                local httpc = http.new()
                local res, err = httpc:request_uri(base .. uri)
                if not res or res.status ~= 200 then
                    ngx.say("request to ", uri, " failed: ", err or res.status)
                    return
                end
                ngx.sleep(0.5)
            end
            ngx.sleep(1)
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
uri: http://127.0.0.1:9200/_bulk, body: {"index":{"_index":"route-a-logs"}}
uri: http://127.0.0.1:9201/_bulk, body: {"index":{"_index":"route-b-logs"}}
--- no_error_log
uri: http://127.0.0.1:9200/_bulk, body: {"index":{"_index":"route-b-logs"}}
failed to get Elasticsearch version
failed to process entries
--- timeout: 5



=== TEST 13: a route whose credentials the cluster rejects
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
                        endpoint_addrs = {"http://127.0.0.1:9201"},
                        field = {
                            index = "services"
                        },
                        auth = {
                            username = "elastic",
                            password = "wrong-password"
                        },
                        batch_max_size = 1,
                    }
                }
            })
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 14: a version probe that failed is not repeated for every request and batch
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            for _ = 1, 3 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                if not res or res.status ~= 200 then
                    ngx.say("request failed: ", err or res.status)
                    return
                end
                -- each entry is sent in a batch of its own, from a timer; let it end
                -- before the next one starts
                ngx.sleep(0.5)
            end
            ngx.say("done")
        }
    }
--- response_body
done
--- grep_error_log eval
qr/failed to get Elasticsearch version/
--- grep_error_log_out
failed to get Elasticsearch version
--- timeout: 10



=== TEST 15: a route on Elasticsearch 6 whose version probe takes a while
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
                        -- Elasticsearch 6 behind the locations of the next block
                        endpoint_addrs = {"http://127.0.0.1:1984/es6"},
                        field = {
                            index = "services"
                        },
                        auth = {
                            username = "elastic",
                            password = "123456"
                        },
                        batch_max_size = 1,
                    }
                }
            })
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 16: requests that come while the first version probe is in flight are logged with `_type`
--- config
    location = /es6 {
        # the version probe answers after half a second
        access_by_lua_block {
            ngx.sleep(0.5)
        }
        proxy_pass http://127.0.0.1:9501/;
    }
    location /es6/ {
        proxy_pass http://127.0.0.1:9501/;
    }
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local threads = {}
            for i = 1, 3 do
                threads[i] = ngx.thread.spawn(function()
                    local res, err = http.new():request_uri(uri)
                    return res and res.status, err
                end)
            end
            for i = 1, 3 do
                local _, status, err = ngx.thread.wait(threads[i])
                if status ~= 200 then
                    ngx.say("request failed: ", status or err)
                    return
                end
            end
            -- Elasticsearch 6 rejects a bulk request whose action line lacks `_type`
            ngx.sleep(2)
            ngx.say("done")
        }
    }
--- response_body
done
--- grep_error_log eval
qr/successfully processed the entries/
--- grep_error_log_out
successfully processed the entries
successfully processed the entries
successfully processed the entries
--- no_error_log
failed to process entries
--- timeout: 10



=== TEST 17: a route on Elasticsearch 6 that rejects requests before elasticsearch-logger's access phase
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
                    ["key-auth"] = {},
                    ["elasticsearch-logger"] = {
                        endpoint_addrs = {"http://127.0.0.1:9501"},
                        field = {
                            index = "services"
                        },
                        auth = {
                            username = "elastic",
                            password = "123456"
                        },
                        batch_max_size = 1,
                    }
                }
            })
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 18: a request rejected before the access phase is logged with `_type`
--- request
GET /hello
--- error_code: 401
--- wait: 2
--- error_log
successfully processed the entries
--- no_error_log
failed to process entries
