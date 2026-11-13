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
BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();
run_tests;

__DATA__

=== TEST 1: validate args operations
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-rewrite")
            local valid = {
                {set = {a = ""}},
                {add = {a = {"x", 2}}},
                {remove = {"a"}},
            }
            for _, args in ipairs(valid) do
                assert(plugin.check_schema({args = args}))
            end
            local invalid = {
                {}, {unknown = {}}, {add = {}}, {set = {}}, {remove = {}},
                {set = {a = {}}}, {add = {a = true}}, {set = {a = {{"x"}}}},
                {remove = {1}}, {set = {[""] = "x"}},
            }
            for _, args in ipairs(invalid) do
                assert(not plugin.check_schema({args = args}))
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: add, set and remove operate on the complete upstream query
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-rewrite")
            local core = require("apisix.core")
            local ctx = {var = {uri = "/original", args = "a=old&a=older&b=keep&c=drop",
                               is_args = "?"}}
            plugin.rewrite({uri = "/new?a=uri&d=uri", args = {
                add = {b = {"extra", "last"}, e = 42},
                set = {a = {"new", "last"}}, remove = {"c", "d"}
            }}, ctx)
            assert(ctx.var.upstream_uri:sub(1, 5) == "/new?")
            local args = core.string.decode_args(ctx.var.upstream_uri:sub(6))
            assert(#args.a == 2 and args.a[1] == "new" and args.a[2] == "last")
            assert(#args.b == 3 and args.b[1] == "keep" and args.b[3] == "last")
            assert(args.e == "42" and not args.c and not args.d)
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 3: encoding, flags, empty values and literal OData expressions
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-rewrite")
            local core = require("apisix.core")
            local ctx = {var = {uri = "/original", args = "flag&empty=&encoded=%2526&plus=a+b",
                               is_args = "?"}}
            local expression = "name eq 'A&B' and age lt 32 $arg_name + % 中文"
            plugin.rewrite({args = {set = {["$filter"] = expression, ["a&b"] = "?=#\r\n"},
                                   add = {flag = "value"}}}, ctx)
            local query = ctx.var.upstream_uri:match("%?(.*)")
            assert(not query:find("\r", 1, true) and not query:find("\n", 1, true))
            local args = core.string.decode_args(query)
            assert(args["$filter"] == expression and args["a&b"] == "?=#\r\n")
            assert(args.flag[1] == true and args.flag[2] == "value")
            assert(args.empty == "" and args.encoded == "%26" and args.plus == "a b")
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 4: remove wins conflicts and an empty query has no question mark
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-rewrite")
            local ctx = {var = {uri = "/original", args = "a=old", is_args = "?"}}
            plugin.rewrite({args = {add = {a = "add"}, set = {a = "set"},
                                   remove = {"a", "absent"}}}, ctx)
            assert(ctx.var.upstream_uri == "/original")
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: more than 100 arguments are retained
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-rewrite")
            local core = require("apisix.core")
            local parts = {}
            for i = 1, 150 do parts[i] = "k" .. i .. "=" .. i end
            local ctx = {var = {uri = "/original", args = table.concat(parts, "&"),
                               is_args = "?"}}
            plugin.rewrite({args = {set = {extra = "yes"}}}, ctx)
            local args = core.string.decode_args(ctx.var.upstream_uri:match("%?(.*)"))
            for i = 1, 150 do assert(args["k" .. i] == tostring(i)) end
            assert(args.extra == "yes")
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 6: regex URI and unsafe URI queries are processed once
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-rewrite")
            local core = require("apisix.core")
            for _, unsafe in ipairs({false, true}) do
                local ctx = {var = {uri = "/original", real_request_uri = "/original?a=old",
                                   args = "a=old", is_args = "?"}}
                plugin.rewrite({use_real_request_uri_unsafe = unsafe,
                                uri = "/new?b=uri", args = {add = {a = "added"}}}, ctx)
                local args = core.string.decode_args(ctx.var.upstream_uri:match("%?(.*)"))
                assert(args.b == "uri" and #args.a == 2 and args.a[1] == "old")
                assert(args.a[2] == "added")
            end
            local ctx = {var = {uri = "/original", args = "a=old", is_args = "?"}}
            plugin.rewrite({regex_uri = {"^/original$", "/new?a=regex"},
                            args = {set = {a = "set"}}}, ctx)
            assert(ctx.var.upstream_uri == "/new?a=set")
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 7: actual upstream receives rewritten parameters on repeated requests
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, {
                uri = "/query-args",
                plugins = {
                    ["proxy-rewrite"] = {
                        uri = "/plugin_proxy_rewrite_args?from=uri&remove=uri",
                        args = {
                            add = {multi = {"added", "last"}},
                            set = {replace = {"new", "final"}, ["$filter"] = "a&b $arg_x"},
                            remove = {"remove"}
                        }
                    }
                },
                upstream = {type = "roundrobin", nodes = {["127.0.0.1:1980"] = 1}}
            })
            assert(code < 300, body)
            local http = require("resty.http")
            local httpc = http.new()
            local url = "http://127.0.0.1:" .. ngx.var.server_port
                .. "/query-args?multi=old&replace=old&remove=client&keep=yes"
            for i = 1, 2 do
                local res = assert(httpc:request_uri(url))
                assert(res.status == 200)
                assert(res.body == "uri: /plugin_proxy_rewrite_args\n"
                    .. "$filter: a&b $arg_x\nfrom: uri\nkeep: yes\n"
                    .. "multi: old,added,last\nreplace: new,final\n", res.body)
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 8: add without an incoming query, set wins add, and keys are case-sensitive
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-rewrite")
            local core = require("apisix.core")
            local conf = {args = {add = {a = {"first", "second"}, A = "upper"},
                                 set = {a = "set", empty = ""}}}
            for i = 1, 2 do
                local ctx = {var = {uri = "/original", is_args = ""}}
                plugin.rewrite(conf, ctx)
                local args = core.string.decode_args(ctx.var.upstream_uri:match("%?(.*)"))
                assert(args.a == "set" and args.A == "upper" and args.empty == "")
                assert(#conf.args.add.a == 2)
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 9: encoded names cannot retain removed arguments in actual upstream requests
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local endpoint = "/print_request_received"
            local variants = {
                {uri = endpoint .. "?token=config"},
                {regex_uri = {"^/print_request_received$", endpoint .. "?token=regex"}},
                {use_real_request_uri_unsafe = true, uri = endpoint .. "?token=config"},
                {use_real_request_uri_unsafe = true},
            }
            local queries = {
                "token=one&token=two&keep=yes",
                "%74oken=one&to%6ben=two&keep=yes",
                "token&token=&keep=yes",
                "token=one&Token=upper&keep=yes",
                "token=one&%2574oken=double&keep=yes",
                "token=one&other=x%26token%3Dhidden&keep=yes",
                "token=one&&keep=yes&",
                "token=one&token%00=suffix&keep=yes",
            }
            for _, conf in ipairs(variants) do
                conf.args = {
                    add = {marker = {"a&token=revive", "%26token=revive", "\r\nX-Evil: 1"}},
                    remove = {"token"}
                }
                local code, body = t('/apisix/admin/routes/11237', ngx.HTTP_PUT, {
                    uri = endpoint,
                    plugins = {["proxy-rewrite"] = conf},
                    upstream = {type = "roundrobin", nodes = {["127.0.0.1:1980"] = 1}}
                })
                assert(code < 300, body)
                for _, query in ipairs(queries) do
                    local res = assert(http.new():request_uri("http://127.0.0.1:"
                        .. ngx.var.server_port .. endpoint .. "?" .. query))
                    assert(res.status == 200, res.body)
                    local raw = assert(res.body:match("^request_uri: ([^\n]+)"), res.body)
                    assert(raw:sub(1, #endpoint + 1) == endpoint .. "?", raw)
                    assert(not res.body:lower():find("\nx%-evil:"), res.body)
                    local args = ngx.decode_args(raw:sub(#endpoint + 2), 0)
                    assert(args.token == nil and args.keep == "yes", raw)
                    assert(#args.marker == 3 and args.marker[1] == "a&token=revive", raw)
                    assert(args.marker[2] == "%26token=revive", raw)
                    assert(args.marker[3] == "\r\nX-Evil: 1", raw)
                    if query:find("Token=", 1, true) then
                        assert(args.Token == "upper", raw)
                    end
                    if query:find("%2574oken", 1, true) then
                        assert(args["%74oken"] == "double", raw)
                    end
                    if query:find("other=", 1, true) then
                        assert(args.other == "x&token=hidden", raw)
                    end
                    if query:find("token%00", 1, true) then
                        assert(args["token\0"] == "suffix", raw)
                    end
                end
            end
            ngx.say("passed: 32 upstream requests")
        }
    }
--- request
GET /t
--- timeout: 20
--- response_body
passed: 32 upstream requests
--- no_error_log
[error]



=== TEST 10: remove covers repeated arguments beyond the first hundred upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local code, body = t('/apisix/admin/routes/11238', ngx.HTTP_PUT, {
                uri = "/many-args",
                plugins = {["proxy-rewrite"] = {
                    uri = "/print_request_received",
                    args = {remove = {"token"}, add = {new = "added"}}
                }},
                upstream = {type = "roundrobin", nodes = {["127.0.0.1:1980"] = 1}}
            })
            assert(code < 300, body)
            local parts = {}
            for i = 1, 250 do parts[i] = "k" .. i .. "=" .. i end
            parts[251] = "token=late&%74oken=last&token"
            local res = assert(http.new():request_uri("http://127.0.0.1:"
                .. ngx.var.server_port .. "/many-args?" .. table.concat(parts, "&")))
            assert(res.status == 200, res.body)
            local raw = assert(res.body:match("^request_uri: ([^\n]+)"), res.body)
            local args = ngx.decode_args(raw:match("%?(.*)"), 0)
            assert(args.token == nil and args.new == "added", raw)
            for i = 1, 250 do assert(args["k" .. i] == tostring(i), raw) end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 11: reject malformed JSON operation shapes
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-rewrite")
            local json = require("cjson.safe")
            local invalid = {
                '{"args":null}', '{"args":true}', '{"args":"x"}',
                '{"args":{"Add":{"a":"b"}}}', '{"args":{"add":[]}}',
                '{"args":{"set":{"a":null}}}', '{"args":{"set":{"a":false}}}',
                '{"args":{"add":{"a":["x",null]}}}',
                '{"args":{"add":{"a":{"nested":"value"}}}}',
                '{"args":{"remove":[""]}}', '{"args":{"remove":"token"}}',
                '{"args":{"remove":["token",false]}}',
                '{"args":{"add":{"":"value"}}}',
            }
            for _, value in ipairs(invalid) do
                assert(not plugin.check_schema(assert(json.decode(value))), value)
            end
            ngx.say("passed: 13 invalid configurations rejected")
        }
    }
--- request
GET /t
--- response_body
passed: 13 invalid configurations rejected
--- no_error_log
[error]



=== TEST 12: remove all arguments upstream without a dangling query separator
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local code, body = t('/apisix/admin/routes/11239', ngx.HTTP_PUT, {
                uri = "/remove-all",
                plugins = {["proxy-rewrite"] = {
                    uri = "/print_request_received?token=config",
                    args = {add = {token = "added"}, set = {token = "set"},
                            remove = {"token", "absent"}}
                }},
                upstream = {type = "roundrobin", nodes = {["127.0.0.1:1980"] = 1}}
            })
            assert(code < 300, body)
            local res = assert(http.new():request_uri("http://127.0.0.1:"
                .. ngx.var.server_port .. "/remove-all?token=one&token=two"))
            assert(res.status == 200, res.body)
            assert(res.body:match("^request_uri: /print_request_received\n"), res.body)
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 13: preserve same-name order and configuration arrays across requests
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.proxy-rewrite")
            local core = require("apisix.core")
            local conf = {args = {add = {a = {"3", "3", 4}}, set = {b = {"8", "9"}}}}
            local function rewrite(query)
                local ctx = {var = {uri = "/original", args = query,
                                   is_args = query and "?" or ""}}
                plugin.rewrite(conf, ctx)
                return core.string.decode_args(ctx.var.upstream_uri:match("%?(.*)"))
            end
            for i = 1, 3 do
                local args = rewrite("a=1&b=old&a=2&b=older")
                assert(table.concat(args.a, ",") == "1,2,3,3,4")
                assert(table.concat(args.b, ",") == "8,9")
                local absent = rewrite(nil)
                assert(table.concat(absent.a, ",") == "3,3,4")
                assert(table.concat(absent.b, ",") == "8,9")
                assert(#conf.args.add.a == 3 and conf.args.add.a[3] == 4)
                assert(#conf.args.set.b == 2 and conf.args.set.b[1] == "8")
            end
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]
