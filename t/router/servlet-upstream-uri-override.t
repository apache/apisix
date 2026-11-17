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
no_shuffle();
no_root_location();
log_level('info');

add_block_preprocessor(sub {
    my ($block) = @_;
    $block->set_value("yaml_config", <<'_EOC_');
apisix:
    node_listen: 1984
    normalize_uri_like_servlet: true
_EOC_
    $block->set_value("upstream_server_config", <<'_EOC_');
    location ~ ^/(anything|other) {
        content_by_lua_block {
            ngx.say(ngx.var.request_uri)
        }
    }
_EOC_
    $block->set_value("http_config", <<'_EOC_');
    server {
        listen 1987;
        location / {
            content_by_lua_block {
                ngx.log(ngx.WARN, "mirror-uri[", ngx.var.request_uri, "]")
                ngx.say("mirrored")
            }
        }
    }
_EOC_
});

run_tests();

__DATA__

=== TEST 1: configure URI overrides and query-only changes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local function rewrite(uri, priority)
                return {
                    use_real_request_uri_unsafe = true,
                    regex_uri = {"^.*$", uri},
                    _meta = {priority = priority or 1100},
                }
            end
            local function access(code)
                return {
                    phase = "access",
                    functions = {"return function(conf, ctx) " .. code .. " end"},
                }
            end
            local mirror = {host = "http://127.0.0.1:1987", sample_ratio = 1}
            local path = "/anything;jsessionid=x"
            local cases = {
                same = {["proxy-rewrite"] = rewrite(path)},
                different = {["proxy-rewrite"] = rewrite("/other?fixed=2")},
                mirror = {["proxy-rewrite"] = rewrite(path), ["proxy-mirror"] = mirror},
                default_order = {
                    ["proxy-rewrite"] = rewrite(path, 1008), ["proxy-mirror"] = mirror,
                },
                args = {["serverless-post-function"] = access(
                    "require('apisix.core').request.set_uri_args(ctx, 'foo=2')")},
                override = {["serverless-post-function"] = access(
                    "ctx.var.upstream_uri = '/anything;jsessionid=x'")},
                later_args = {
                    ["proxy-rewrite"] = rewrite(path),
                    ["serverless-post-function"] = access("ngx.req.set_uri_args('foo=2')"),
                },
                clear = {
                    ["proxy-rewrite"] = rewrite("/other"),
                    ["serverless-post-function"] = access(
                        "ctx.var.upstream_uri = ''; ngx.req.set_uri_args('foo=2')"),
                },
                untouched = {},
                native = {
                    ["serverless-pre-function"] = {
                        phase = "rewrite",
                        functions = {[[return function(conf, ctx)
                            ngx.var.upstream_uri = '/other?fixed=2'
                            ctx.var._cache.upstream_uri = nil
                        end]]},
                    },
                    ["proxy-mirror"] = mirror,
                },
            }
            for name, plugins in pairs(cases) do
                local code, body = t("/apisix/admin/routes/servlet-override-" .. name,
                    ngx.HTTP_PUT, {
                        uri = "/anything",
                        host = name .. ".test",
                        plugins = plugins,
                        upstream = {
                            type = "roundrobin",
                            nodes = {["127.0.0.1:1980"] = 1},
                        },
                    })
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



=== TEST 2: same-path rewrite removes the query
--- request
GET /anything;jsessionid=x?foo=1
--- more_headers
Host: same.test
--- response_body
/anything;jsessionid=x



=== TEST 3: explicit URI retains its own query
--- request
GET /anything;jsessionid=x?foo=1
--- more_headers
Host: different.test
--- response_body
/other?fixed=2



=== TEST 4: mirror after rewrite preserves the explicit same-path URI
--- request
GET /anything;jsessionid=x?foo=1
--- more_headers
Host: mirror.test
--- response_body
/anything;jsessionid=x
--- error_log
mirror-uri[/anything;jsessionid=x]
--- no_error_log
[error]
mirror-uri[/anything;jsessionid=x?foo=1]



=== TEST 5: mirror before rewrite still observes the original query
--- request
GET /anything;jsessionid=x?foo=1
--- more_headers
Host: default_order.test
--- response_body
/anything;jsessionid=x
--- error_log
mirror-uri[/anything;jsessionid=x?foo=1]
--- no_error_log
[error]



=== TEST 6: query-only access changes are appended to the servlet path
--- request
GET /anything;jsessionid=x?foo=1
--- more_headers
Host: args.test
--- response_body
/anything;jsessionid=x?foo=2



=== TEST 7: an access plugin can explicitly remove the query
--- request
GET /anything;jsessionid=x?foo=1
--- more_headers
Host: override.test
--- response_body
/anything;jsessionid=x



=== TEST 8: later query changes do not replace an explicit upstream URI
--- request
GET /anything;jsessionid=x?foo=1
--- more_headers
Host: later_args.test
--- response_body
/anything;jsessionid=x



=== TEST 9: clearing an override restores servlet path and live query fallback
--- request
GET /anything;jsessionid=x?foo=1
--- more_headers
Host: clear.test
--- response_body
/anything;jsessionid=x?foo=2



=== TEST 10: override state does not leak to the next request
--- config
    location /t {
        content_by_lua_block {
            local httpc = require("resty.http").new()
            for _, host in ipairs({"same.test", "untouched.test"}) do
                local res = assert(httpc:request_uri(
                    "http://127.0.0.1:1984/anything;jsessionid=x?foo=1", {
                        headers = {Host = host},
                    }))
                assert(res.status == 200)
                ngx.print(res.body)
            end
        }
    }
--- request
GET /t
--- response_body
/anything;jsessionid=x
/anything;jsessionid=x?foo=1



=== TEST 11: preserve a different URI even if its assignment bypasses ctx.var
--- request
GET /anything;jsessionid=x?foo=1
--- more_headers
Host: native.test
--- response_body
/other?fixed=2
--- error_log
mirror-uri[/other?fixed=2]
--- no_error_log
[error]



=== TEST 12: delete routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            for _, name in ipairs({"same", "different", "mirror", "default_order", "args",
                                   "override", "later_args", "clear", "untouched", "native"}) do
                local code, body = t("/apisix/admin/routes/servlet-override-" .. name,
                    ngx.HTTP_DELETE)
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
