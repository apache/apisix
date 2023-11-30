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

log_level('warn');
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $user_yaml_config = <<_EOC_;
plugin_attr:
  inspect:
    delay: 1
    hooks_file: "/tmp/apisix_inspect_hooks.lua"
_EOC_
    $block->set_value("yaml_config", $user_yaml_config);

    my $extra_init_worker_by_lua = $block->extra_init_worker_by_lua // "";
    $extra_init_worker_by_lua .= <<_EOC_;
local function gen_funcs_invoke(...)
    local code = ""
    for _, func in ipairs({...}) do
        code = code .. "test." .. func .. "();"
    end
    return code
end
function set_test_route(...)
    func = func or 'run1'
    local t = require("lib.test_admin").test
    local code = [[{
        "methods": ["GET"],
        "uri": "/inspect",
        "plugins": {
            "serverless-pre-function": {
                "phase": "rewrite",
                "functions" : ["return function() local test = require(\\"lib.test_inspect\\");]]
                .. gen_funcs_invoke(...)
                .. [[ngx.say(\\"ok\\"); end"]
            }
        },
        "upstream": {
            "type": "roundrobin",
            "nodes": {
                "127.0.0.1:1980": 1
            }
        }
    }]]
    return t('/apisix/admin/routes/inspect', ngx.HTTP_PUT, code)
end

function do_request()
    local http = require "resty.http"
    local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/inspect"

    local httpc = http.new()
    local res = httpc:request_uri(uri, {method = "GET"})
    assert(res.body == "ok\\n")
end

function write_hooks(code, file)
    local file = io.open(file or "/tmp/apisix_inspect_hooks.lua", "w")
    file:write(code)
    file:close()
end
_EOC_
    $block->set_value("extra_init_worker_by_lua", $extra_init_worker_by_lua);

    # note that it's different from APISIX.pm,
    # here we enable no_error_log ignoreless of error_log.
    if (!$block->no_error_log) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!$block->timeout) {
        $block->set_value("timeout", "10");
    }
});

add_cleanup_handler(sub {
    unlink("/tmp/apisix_inspect_hooks.lua");
});

run_tests;

__DATA__

=== TEST 1: simple hook
--- config
    location /t {
        content_by_lua_block {
            local code = set_test_route("run1")
            if code >= 300 then
                ngx.status = code
                return
            end

            write_hooks([[
            local dbg = require "apisix.inspect.dbg"
            dbg.set_hook("t/lib/test_inspect.lua", 27, nil, function(info)
                ngx.log(ngx.WARN, "var1=", info.vals.var1)
                return true
            end)
            ]])

            ngx.sleep(1.5)

            do_request()

            os.remove("/tmp/apisix_inspect_hooks.lua")
        }
    }
--- error_log
var1=hello



=== TEST 2: filename only
--- config
    location /t {
        content_by_lua_block {
            local code = set_test_route("run1")
            if code >= 300 then
                ngx.status = code
                return
            end

            write_hooks([[
            local dbg = require "apisix.inspect.dbg"
            dbg.set_hook("test_inspect.lua", 27, nil, function(info)
                ngx.log(ngx.WARN, "var1=", info.vals.var1)
                return true
            end)
            ]])

            ngx.sleep(1.5)

            do_request()

            os.remove("/tmp/apisix_inspect_hooks.lua")
        }
    }
--- error_log
var1=hello



=== TEST 3: hook lifetime
--- config
    location /t {
        content_by_lua_block {
            local code = set_test_route("run1")
            if code >= 300 then
                ngx.status = code
                return
            end

            write_hooks([[
            local dbg = require "apisix.inspect.dbg"
            local hook1_times = 2
            dbg.set_hook("test_inspect.lua", 27, nil, function(info)
                ngx.log(ngx.WARN, "var1=", info.vals.var1)
                hook1_times = hook1_times - 1
                return hook1_times == 0
            end)
            ]])

            ngx.sleep(1.5)

            -- request 3 times, but hook triggered 2 times
            for _ = 1,3 do
                do_request()
            end

            os.remove("/tmp/apisix_inspect_hooks.lua")
        }
    }
--- error_log
var1=hello
var1=hello



=== TEST 4: multiple hooks
--- config
    location /t {
        content_by_lua_block {
            local code = set_test_route("run1")
            if code >= 300 then
                ngx.status = code
                return
            end

            write_hooks([[
            local dbg = require "apisix.inspect.dbg"
            dbg.set_hook("test_inspect.lua", 26, nil, function(info)
                ngx.log(ngx.WARN, "var1=", info.vals.var1)
                return true
            end)

            dbg.set_hook("test_inspect.lua", 27, nil, function(info)
                ngx.log(ngx.WARN, "var2=", info.vals.var2)
                return true
            end)
            ]])

            ngx.sleep(1.5)

            do_request()

            -- note that we don't remove the hook file,
            -- used for next test case
        }
    }
--- error_log
var1=hello
var2=world



=== TEST 5: hook file not removed, re-enabled by next startup
--- config
    location /t {
        content_by_lua_block {
            local code = set_test_route("run1")
            if code >= 300 then
                ngx.status = code
                return
            end

            do_request()

            os.remove("/tmp/apisix_inspect_hooks.lua")
        }
    }
--- error_log
var1=hello



=== TEST 6: soft link
--- config
    location /t {
        content_by_lua_block {
            local code = set_test_route("run1")
            if code >= 300 then
                ngx.status = code
                return
            end

            write_hooks([[
            local dbg = require "apisix.inspect.dbg"
            dbg.set_hook("t/lib/test_inspect.lua", 27, nil, function(info)
                ngx.log(ngx.WARN, "var1=", info.vals.var1)
                return true
            end)
            ]], "/tmp/test_real_tmp_file.lua")

            os.execute("ln -sf /tmp/test_real_tmp_file.lua /tmp/apisix_inspect_hooks.lua")

            ngx.sleep(1.5)

            do_request()

            os.remove("/tmp/apisix_inspect_hooks.lua")
            os.remove("/tmp/test_real_tmp_file.lua")
        }
    }
--- error_log
var1=hello



=== TEST 7: remove soft link would disable hooks
--- config
    location /t {
        content_by_lua_block {
            local code = set_test_route("run1")
            if code >= 300 then
                ngx.status = code
                return
            end

            write_hooks([[
            local dbg = require "apisix.inspect.dbg"
            dbg.set_hook("t/lib/test_inspect.lua", 27, nil, function(info)
                ngx.log(ngx.WARN, "var1=", info.vals.var1)
                return true
            end)
            ]], "/tmp/test_real_tmp_file.lua")

            os.execute("ln -sf /tmp/test_real_tmp_file.lua /tmp/apisix_inspect_hooks.lua")

            ngx.sleep(1.5)
            os.remove("/tmp/apisix_inspect_hooks.lua")
            ngx.sleep(1.5)

            do_request()

            os.remove("/tmp/test_real_tmp_file.lua")
        }
    }
--- no_error_log
var1=hello



=== TEST 8: ensure we see all local variables till the hook line
--- config
    location /t {
        content_by_lua_block {
            local code = set_test_route("run1")
            if code >= 300 then
                ngx.status = code
                return
            end

            write_hooks([[
            local dbg = require "apisix.inspect.dbg"
            dbg.set_hook("t/lib/test_inspect.lua", 27, nil, function(info)
                local count = 0
                for k,v in pairs(info.vals) do
                    count = count + 1
                end
                ngx.log(ngx.WARN, "count=", count)
                return true
            end)
            ]])

            ngx.sleep(1.5)

            do_request()

            os.remove("/tmp/apisix_inspect_hooks.lua")
        }
    }
--- error_log
count=2



=== TEST 9: check upvalue of run2(), only upvalue used in function code are visible
--- config
    location /t {
        content_by_lua_block {
            local code = set_test_route("run2")
            if code >= 300 then
                ngx.status = code
                return
            end

            write_hooks([[
            local dbg = require "apisix.inspect.dbg"
            dbg.set_hook("t/lib/test_inspect.lua", 33, nil, function(info)
                ngx.log(ngx.WARN, "upvar1=", info.uv.upvar1)
                ngx.log(ngx.WARN, "upvar2=", info.uv.upvar2)
                return true
            end)
            ]])

            ngx.sleep(1.5)

            do_request()

            os.remove("/tmp/apisix_inspect_hooks.lua")
        }
    }
--- error_log
upvar1=2
upvar2=nil



=== TEST 10: check upvalue of run3(), now both upvar1 and upvar2 are visible
--- config
    location /t {
        content_by_lua_block {
            local code = set_test_route("run3")
            if code >= 300 then
                ngx.status = code
                return
            end

            write_hooks([[
            local dbg = require "apisix.inspect.dbg"
            dbg.set_hook("t/lib/test_inspect.lua", 37, nil, function(info)
                ngx.log(ngx.WARN, "upvar1=", info.uv.upvar1)
                ngx.log(ngx.WARN, "upvar2=", info.uv.upvar2)
                return true
            end)
            ]])

            ngx.sleep(1.5)

            do_request()

            os.remove("/tmp/apisix_inspect_hooks.lua")
        }
    }
--- error_log
upvar1=2
upvar2=yes



=== TEST 11: flush specific JIT cache
--- config
    location /t {
        content_by_lua_block {
            local test = require("lib.test_inspect")

            local t1 = test.hot1()
            local t8 = test.hot2()

            write_hooks([[
            local test = require("lib.test_inspect")
            local dbg = require "apisix.inspect.dbg"
            dbg.set_hook("t/lib/test_inspect.lua", 47, test.hot1, function(info)
                return false
            end)
            ]])

            ngx.sleep(1.5)

            local t2 = test.hot1()
            local t9 = test.hot2()

            assert(t2-t1 > t1, "hot1 consumes at least double times than before")
            assert(t9-t8 < t8*0.8, "hot2 not affected")

            os.remove("/tmp/apisix_inspect_hooks.lua")

            ngx.sleep(1.5)

            local t3 = test.hot1()
            local t4 = test.hot2()
            assert(t3-t1 < t1*0.8, "hot1 jit recover")
            assert(t4-t8 < t4*0.8, "hot2 jit recover")
        }
    }



=== TEST 12: flush the whole JIT cache
--- config
    location /t {
        content_by_lua_block {
            local test = require("lib.test_inspect")

            local t1 = test.hot1()
            local t8 = test.hot2()

            write_hooks([[
            local test = require("lib.test_inspect")
            local dbg = require "apisix.inspect.dbg"
            dbg.set_hook("t/lib/test_inspect.lua", 47, nil, function(info)
                return false
            end)
            ]])

            ngx.sleep(1.5)

            local t2 = test.hot1()
            local t9 = test.hot2()

            assert(t2-t1 > t1, "hot1 consumes at least double times than before")
            assert(t9-t8 > t8, "hot2 consumes at least double times than before")

            os.remove("/tmp/apisix_inspect_hooks.lua")

            ngx.sleep(1.5)

            local t3 = test.hot1()
            local t4 = test.hot2()
            assert(t3-t1 < t1*0.8, "hot1 jit recover")
            assert(t4-t8 < t4*0.8, "hot2 jit recover")
        }
    }



=== TEST 13: remove hook log
--- config
    location /t {
        content_by_lua_block {
            local code = set_test_route("run1")
            if code >= 300 then
                ngx.status = code
                return
            end

            write_hooks([[
            local dbg = require "apisix.inspect.dbg"
            dbg.set_hook("t/lib/test_inspect.lua", 27, nil, function(info)
                return true
            end)
            ]])

            ngx.sleep(1.5)

            do_request()

            os.remove("/tmp/apisix_inspect_hooks.lua")
        }
    }
--- error_log
inspect: remove hook: t/lib/test_inspect.lua#27
inspect: all hooks removed



=== TEST 14: jit should be recovered after all hooks are done
--- config
    location /t {
        content_by_lua_block {
            local test = require("lib.test_inspect")

            local t1 = test.hot1()

            write_hooks([[
            local test = require("lib.test_inspect")
            local dbg = require "apisix.inspect.dbg"
            dbg.set_hook("t/lib/test_inspect.lua", 47, test.hot1, function(info)
                return true
            end)
            ]])

            ngx.sleep(1.5)

            local t2 = test.hot1()
            assert(t2-t1 < t1*0.8, "hot1 consumes at least double times than before")
        }
    }
--- error_log
inspect: remove hook: t/lib/test_inspect.lua#47
inspect: all hooks removed
