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

add_block_preprocessor(sub {
    my ($block) = @_;

my $user_yaml_config = <<_EOC_;
plugins:
  - toolset
  - serverless-post-function
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: create route with uri "/*"
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/*",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                        "127.0.0.1:1980": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: match against pattern "*.com"
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local file, err = io.open("apisix/plugins/toolset/config.lua", "w+")
            if not file then
                ngx.status = 500
                ngx.say("Failed test: failed to open config file")
                return
            end
            local old = file:read("*all")
            file:write([[
return {
  trace = {
    rate = 100,
    hosts = {"*.com"}
  }
}
]])
            file:close()


            ngx.sleep(2)

            local httpc = http.new()

            -- correct path, correct host = trace
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {headers = { ["Host"] = "abc.com" }})
        }
    }
--- grep_error_log eval
qr/trace:/
--- grep_error_log_out
trace:



=== TEST 3: match against pattern "*.com"
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local file, err = io.open("apisix/plugins/toolset/config.lua", "w+")
            if not file then
                ngx.status = 500
                ngx.say("Failed test: failed to open config file")
                return
            end
            local old = file:read("*all")
            file:write([[
return {
  trace = {
    rate = 100,
    hosts = {"*.com"},
    paths = {"/hello"}
  }
}
]])
            file:close()


            ngx.sleep(2)

            local httpc = http.new()

            -- incorrect path, incorrect host = dont_trace
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/nohello/abc"
            local res, err = httpc:request_uri(uri, {headers = { ["Host"] = "abc.com.cde" }})
        }
    }
--- no_error_log
trace:



=== TEST 4: match against pattern "abc.*" correct path, correct host = trace
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local file, err = io.open("apisix/plugins/toolset/config.lua", "w+")
            if not file then
                ngx.status = 500
                ngx.say("Failed test: failed to open config file")
                return
            end
            local old = file:read("*all")
            file:write([[
return {
  trace = {
    rate = 100,
    hosts = {"abc.*"},
    paths = {"/hello"}
  }
}
]])
            file:close()


            ngx.sleep(2)

            local http = require("resty.http")
            local httpc = http.new()

            -- correct path, correct host = trace
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {headers = { ["Host"] = "abc.com" }})
        }
    }
--- grep_error_log eval
qr/trace:/
--- grep_error_log_out
trace:



=== TEST 5: match against pattern "abc.*"" incorrect path, correct host = trace
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")
            local httpc = http.new()

            local file, err = io.open("apisix/plugins/toolset/config.lua", "w+")
            if not file then
                ngx.status = 500
                ngx.say("Failed test: failed to open config file")
                return
            end
            local old = file:read("*all")
            file:write([[
return {
  trace = {
    rate = 1,
    hosts = {"abc.*"},
    paths = {"/hello"}
  }
}
]])
            file:close()


            ngx.sleep(2)

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/nohello"
            local res, err = httpc:request_uri(uri, {headers = { ["Host"] = "abc.com" }})
        }
    }
--- grep_error_log eval
qr/trace:/
--- grep_error_log_out
trace:
