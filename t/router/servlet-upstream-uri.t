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
log_level('info');
worker_connections(256);
no_root_location();
no_shuffle();

our $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    normalize_uri_like_servlet: true
    router:
        http: 'radixtree_uri'
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->yaml_config) {
        $block->set_value("yaml_config", $yaml_config);
    }

    if (!$block->upstream_server_config) {
        $block->set_value("upstream_server_config", <<'_EOC_');
        location = /anything {
            content_by_lua_block {
                ngx.say("protected-handler")
                ngx.say("route-marker=", ngx.var.http_x_route_marker or "")
                ngx.say("request-uri=", ngx.var.request_uri)
            }
        }

        location /anything {
            content_by_lua_block {
                ngx.say("path-handler")
                ngx.say("route-marker=", ngx.var.http_x_route_marker or "")
                ngx.say("request-uri=", ngx.var.request_uri)
            }
        }

        location /early-plugin {
            content_by_lua_block {
                ngx.say("observed-upstream-uri=", ngx.var.http_x_observed_upstream_uri or "")
                ngx.say("request-uri=", ngx.var.request_uri)
            }
        }

        location /data-mask {
            content_by_lua_block {
                ngx.say("data-mask-handler")
                ngx.say("request-uri=", ngx.var.request_uri)
            }
        }
_EOC_
    }
});

run_tests();

__DATA__

=== TEST 1: set overlapping exact and wildcard routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t("/apisix/admin/consumers",
                ngx.HTTP_PUT,
                {
                    username = "jack",
                    plugins = {
                        ["key-auth"] = {
                            key = "secret-key",
                        },
                    },
                }
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local routes = {
                {
                    id = "protected-exact-path",
                    host = "servlet-uri.test",
                    priority = 100000,
                    uri = "/anything",
                    plugins = {
                        ["key-auth"] = {
                            hide_credentials = true,
                        },
                    },
                },
                {
                    id = "public-wildcard-fallback",
                    host = "servlet-uri.test",
                    priority = 100000,
                    uri = "/*",
                    plugins = {
                        ["request-id"] = {
                            algorithm = "range_id",
                            header_name = "X-Route-Marker",
                            include_in_response = false,
                            range_id = {
                                char_set = "abcdef",
                                length = 6,
                            },
                        },
                    },
                },
                {
                    id = "early-plugin-test",
                    host = "servlet-uri.test",
                    priority = 100001,
                    uri = "/early-plugin/*",
                    plugins = {
                        ["serverless-pre-function"] = {
                            phase = "rewrite",
                            functions = {
                                "return function(conf, ctx) ngx.req.set_header('X-Observed-Upstream-Uri', ctx.var.upstream_uri or '') end",
                            },
                        },
                    },
                },
                {
                    id = "data-mask-test",
                    host = "servlet-uri.test",
                    priority = 100002,
                    uri = "/data-mask",
                    plugins = {
                        ["data-mask"] = {
                            request = {
                                {
                                    action = "remove",
                                    name = "password",
                                    type = "query",
                                },
                            },
                        },
                        ["file-logger"] = {
                            path = "mask-servlet-upstream.log",
                            log_format = {
                                request_line = "$request_line",
                                upstream_uri = "$upstream_uri",
                            },
                        },
                    },
                },
            }

            for _, route in ipairs(routes) do
                route.upstream = {
                    nodes = { ["127.0.0.1:1980"] = 1 },
                    type = "roundrobin",
                }

                code, body = t("/apisix/admin/routes/" .. route.id,
                    ngx.HTTP_PUT, route)
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
            end

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: exact route requires an API key
--- request
GET /anything
--- more_headers
Host: servlet-uri.test
--- error_code: 401
--- response_body
{"message":"Missing API key in request"}



=== TEST 3: encoded question mark remains path data upstream
--- request
GET /anything%3Fprobe;jsessionid=x
--- more_headers
Host: servlet-uri.test
--- response_body_like eval
qr/^path-handler\nroute-marker=[a-f]{6}\nrequest-uri=\/anything%3Fprobe;jsessionid=x\n$/
--- no_error_log
[error]



=== TEST 4: query string is preserved when normalize_uri_like_servlet is on
--- request
GET /anything/sub;jsessionid=x?foo=1&bar=2
--- more_headers
Host: servlet-uri.test
--- response_body_like eval
qr/^path-handler\nroute-marker=[a-f]{6}\nrequest-uri=\/anything\/sub;jsessionid=x\?foo=1&bar=2\n$/
--- no_error_log
[error]



=== TEST 5: query modifications (key-auth hide_credentials) are preserved during servlet normalization
--- request
GET /anything;jsessionid=x?apikey=secret-key&foo=1
--- more_headers
Host: servlet-uri.test
--- response_body eval
"path-handler\nroute-marker=\nrequest-uri=/anything;jsessionid=x?foo=1\n"
--- no_error_log
[error]



=== TEST 6: when all query args are stripped by hide_credentials, no trailing question mark is sent upstream
--- request
GET /anything;jsessionid=x?apikey=secret-key
--- more_headers
Host: servlet-uri.test
--- response_body eval
"path-handler\nroute-marker=\nrequest-uri=/anything;jsessionid=x\n"
--- no_error_log
[error]



=== TEST 7: early plugins (rewrite/access phase) observe servlet path parameters in upstream_uri
--- request
GET /early-plugin/test;jsessionid=x?foo=1
--- more_headers
Host: servlet-uri.test
--- response_body eval
"observed-upstream-uri=/early-plugin/test;jsessionid=x\nrequest-uri=/early-plugin/test;jsessionid=x?foo=1\n"
--- no_error_log
[error]



=== TEST 8: data-mask sanitizes upstream_uri and request_line when servlet normalization is on
--- request
GET /data-mask;jsessionid=x?password=secret
--- more_headers
Host: servlet-uri.test
--- response_body eval
"data-mask-handler\nrequest-uri=/data-mask;jsessionid=x?password=secret\n"
--- no_error_log
[error]



=== TEST 9: verify log contains masked request_line and sanitized upstream_uri
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local fd, err = io.open("mask-servlet-upstream.log", "r")
            if not fd then
                core.log.error("failed to open file: ", err)
                return
            end
            local line = fd:read()
            fd:close()
            os.remove("mask-servlet-upstream.log")

            local log = core.json.decode(line)
            if log.request_line ~= "GET /data-mask HTTP/1.1" then
                ngx.say("unexpected request_line: ", log.request_line)
                return
            end
            if log.upstream_uri ~= "/data-mask;jsessionid=x" then
                ngx.say("unexpected upstream_uri: ", log.upstream_uri)
                return
            end

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 10: data-mask preserves remaining query args in upstream_uri during servlet normalization
--- request
GET /data-mask;jsessionid=x?password=secret&foo=1
--- more_headers
Host: servlet-uri.test
--- response_body eval
"data-mask-handler\nrequest-uri=/data-mask;jsessionid=x?password=secret&foo=1\n"
--- no_error_log
[error]



=== TEST 11: verify log preserves remaining query args in request_line and upstream_uri
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local fd, err = io.open("mask-servlet-upstream.log", "r")
            if not fd then
                core.log.error("failed to open file: ", err)
                return
            end
            local line = fd:read()
            fd:close()
            os.remove("mask-servlet-upstream.log")

            local log = core.json.decode(line)
            if log.request_line ~= "GET /data-mask?foo=1 HTTP/1.1" then
                ngx.say("unexpected request_line: ", log.request_line)
                return
            end
            if log.upstream_uri ~= "/data-mask;jsessionid=x?foo=1" then
                ngx.say("unexpected upstream_uri: ", log.upstream_uri)
                return
            end

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 12: delete routes and consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local route_ids = {
                "protected-exact-path",
                "public-wildcard-fallback",
                "early-plugin-test",
                "data-mask-test",
            }

            for _, route_id in ipairs(route_ids) do
                local code, body = t("/apisix/admin/routes/" .. route_id,
                    ngx.HTTP_DELETE)
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
            end

            local code, body = t("/apisix/admin/consumers/jack",
                ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
