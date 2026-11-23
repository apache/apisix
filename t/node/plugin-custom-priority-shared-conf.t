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

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: plugin_config shared by two routes, one of them adds a plugin with a custom priority
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_configs/1', ngx.HTTP_PUT,
                [[{"plugins": {"response-rewrite": {"headers": {"set": {"X-PC": "1"}}}}}]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT,
                [[{"uri": "/hello", "plugin_config_id": "1",
                   "plugins": {"proxy-rewrite": {"headers": {"set": {"X-R": "1"}},
                                                 "_meta": {"priority": 100}}},
                   "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"}}]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/2', ngx.HTTP_PUT,
                [[{"uri": "/hello1", "plugin_config_id": "1",
                   "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"}}]])
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



=== TEST 2: the custom sort of one route gives no priority to the shared plugin_config conf
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local base = "http://127.0.0.1:" .. ngx.var.server_port
            for _, path in ipairs({"/hello", "/hello1"}) do
                local res = http.new():request_uri(base .. path)
                ngx.say(path, " ", res.status, " ", res.headers["X-PC"])
            end

            local conf = require("apisix.plugin_config").get("1")
                            .value.plugins["response-rewrite"]
            ngx.say("priority: ", conf._meta and conf._meta.priority)
        }
    }
--- response_body
/hello 200 1
/hello1 200 1
priority: nil



=== TEST 3: a consumer plugin with a custom priority, merged into a route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            t('/apisix/admin/routes/2', ngx.HTTP_DELETE)
            t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            local code, body = t('/apisix/admin/consumers', ngx.HTTP_PUT,
                [[{"username": "jack", "plugins": {"key-auth": {"key": "jack"},
                   "proxy-rewrite": {"headers": {"set": {"X-C": "1"}},
                                     "_meta": {"priority": 1}}}}]])
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/3', ngx.HTTP_PUT,
                [[{"uri": "/hello", "plugins": {"key-auth": {},
                   "response-rewrite": {"headers": {"set": {"X-R": "1"}}}},
                   "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"}}]])
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



=== TEST 4: the custom sort of the merged route gives no priority to the consumer's or the route's confs
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res = http.new():request_uri(uri, {headers = {apikey = "jack"}})
            ngx.say(res.status, " ", res.headers["X-R"])

            for _, consumer in ipairs(require("apisix.consumer").consumers()) do
                if consumer.value.username == "jack" then
                    local conf = consumer.value.plugins["key-auth"]
                    ngx.say("consumer key-auth priority: ", conf._meta and conf._meta.priority)
                end
            end

            for _, route in ipairs(require("apisix.router").http_routes()) do
                if route.value.id == "3" then
                    local conf = route.value.plugins["response-rewrite"]
                    ngx.say("route response-rewrite priority: ", conf._meta and conf._meta.priority)
                end
            end
        }
    }
--- response_body
200 1
consumer key-auth priority: nil
route response-rewrite priority: nil
