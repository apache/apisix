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
use File::Temp qw(tempdir);

repeat_each(1);
log_level('info');
no_long_string();
no_root_location();
no_shuffle();

my $cache_dir = tempdir(TMPDIR => 1, CLEANUP => 1);

add_block_preprocessor(sub {
    my ($block) = @_;

    my $http_config = $block->http_config // <<_EOC_;
    proxy_cache_path $cache_dir levels=1:2 keys_zone=disk_cache_one:50m inactive=1d max_size=1G;

    map \$upstream_cache_zone \$upstream_cache_zone_info {
        disk_cache_one $cache_dir,1:2;
    }
_EOC_
    $block->set_value("http_config", $http_config);

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: a service limit-count shared by two routes, one of them with a custom plugin priority
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1', ngx.HTTP_PUT, [[{
                "plugins": {"limit-count": {"count": 2, "time_window": 60, "rejected_code": 503,
                                            "key": "remote_addr", "policy": "local"}},
                "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"}}]])
            assert(code < 300, body)
            code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/hello", "host": "a.test", "service_id": "1",
                "plugins": {"proxy-rewrite": {"headers": {"set": {"X-A": "1"}},
                                              "_meta": {"priority": 100}}}}]])
            assert(code < 300, body)
            code, body = t('/apisix/admin/routes/2', ngx.HTTP_PUT, [[{
                "uri": "/hello", "host": "b.test", "service_id": "1"}]])
            assert(code < 300, body)
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: both routes count on the one quota of the service
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            for _, host in ipairs({"a.test", "b.test", "a.test"}) do
                local res = http.new():request_uri(uri, {headers = {Host = host}})
                ngx.say(host, " ", res.status)
            end
        }
    }
--- response_body
a.test 200
b.test 200
a.test 503



=== TEST 3: the same with limit-req
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1', ngx.HTTP_PUT, [[{
                "plugins": {"limit-req": {"rate": 1, "burst": 0, "rejected_code": 503,
                                          "key": "remote_addr"}},
                "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"}}]])
            assert(code < 300, body)
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 4: a request on one route uses up the rate of the other
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            for _, host in ipairs({"a.test", "b.test"}) do
                local res = http.new():request_uri(uri, {headers = {Host = host}})
                ngx.say(host, " ", res.status)
            end
        }
    }
--- response_body
a.test 200
b.test 503



=== TEST 5: the same with limit-conn
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1', ngx.HTTP_PUT, [[{
                "plugins": {"limit-conn": {"conn": 1, "burst": 0, "default_conn_delay": 0.1,
                                           "rejected_code": 503, "key": "remote_addr"}},
                "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"}}]])
            assert(code < 300, body)
            for id, host in pairs({["1"] = "a.test", ["2"] = "b.test"}) do
                local route = {uri = "/mysleep", host = host, service_id = "1"}
                if id == "1" then
                    route.plugins = {["proxy-rewrite"] = {headers = {set = {["X-A"] = "1"}},
                                                          _meta = {priority = 100}}}
                end
                code, body = t('/apisix/admin/routes/' .. id, ngx.HTTP_PUT, route)
                assert(code < 300, body)
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 6: a connection on one route counts on the other
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/mysleep?seconds=1"
            local th = ngx.thread.spawn(function()
                return http.new():request_uri(uri, {headers = {Host = "a.test"}})
            end)
            ngx.sleep(0.3)
            local res = http.new():request_uri(uri, {headers = {Host = "b.test"}})
            local _, first = ngx.thread.wait(th)
            ngx.say("a.test ", first.status)
            ngx.say("b.test ", res.status)
        }
    }
--- response_body
a.test 200
b.test 503



=== TEST 7: consumer jack with a redis limit-count of 2; route 1 has a custom plugin priority
--- config
    location /t {
        content_by_lua_block {
            local redis = require("resty.redis").new()
            assert(redis:connect("127.0.0.1", 6379))
            redis:flushall()
            local t = require("lib.test_admin").test
            t('/apisix/admin/services/1', ngx.HTTP_DELETE)
            local code, body = t('/apisix/admin/consumers', ngx.HTTP_PUT, [[{
                "username": "jack",
                "plugins": {
                    "key-auth": {"key": "jack"},
                    "limit-count": {"count": 2, "time_window": 600, "rejected_code": 503,
                                    "key": "remote_addr", "policy": "redis",
                                    "redis_host": "127.0.0.1"}
                }}]])
            assert(code < 300, body)
            code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, [[{
                "uri": "/hello", "host": "a.test",
                "plugins": {"key-auth": {},
                            "proxy-rewrite": {"headers": {"set": {"X-A": "1"}},
                                              "_meta": {"priority": 100}}},
                "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"}}]])
            assert(code < 300, body)
            code, body = t('/apisix/admin/routes/2', ngx.HTTP_PUT, [[{
                "uri": "/hello", "host": "b.test",
                "plugins": {"key-auth": {}},
                "upstream": {"nodes": {"127.0.0.1:1980": 1}, "type": "roundrobin"}}]])
            assert(code < 300, body)
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 8: a node whose first request of jack is on route 2
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.5)
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res = http.new():request_uri(uri, {headers = {Host = "b.test", apikey = "jack"}})
            ngx.say("b.test ", res.status)
        }
    }
--- response_body
b.test 200



=== TEST 9: a node whose first request of jack is on route 1 shares the quota of the first node
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.5)
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            for _, host in ipairs({"a.test", "a.test"}) do
                local res = http.new():request_uri(uri, {headers = {Host = host, apikey = "jack"}})
                ngx.say(host, " ", res.status)
            end
        }
    }
--- response_body
a.test 200
a.test 503



=== TEST 10: consumer jack with a graphql-proxy-cache on disk instead
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers', ngx.HTTP_PUT, [[{
                "username": "jack",
                "plugins": {
                    "key-auth": {"key": "jack"},
                    "graphql-proxy-cache": {}
                }}]])
            assert(code < 300, body)
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 11: a node whose first request of jack is on route 2 caches the response
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.5)
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local query = '{"query": "query{conf_version_order{id}}"}'
            for _ = 1, 2 do
                local res = http.new():request_uri(uri, {method = "POST", body = query,
                    headers = {Host = "b.test", apikey = "jack",
                               ["Content-Type"] = "application/json"}})
                ngx.say("b.test ", res.status, " ", res.headers["Apisix-Cache-Status"])
            end
        }
    }
--- response_body
b.test 200 MISS
b.test 200 HIT



=== TEST 12: a node whose first request of jack is on route 1 hits the same cache entry
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(0.5)
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local query = '{"query": "query{conf_version_order{id}}"}'
            for _, host in ipairs({"a.test", "b.test"}) do
                local res = http.new():request_uri(uri, {method = "POST", body = query,
                    headers = {Host = host, apikey = "jack",
                               ["Content-Type"] = "application/json"}})
                ngx.say(host, " ", res.status, " ", res.headers["Apisix-Cache-Status"])
            end
        }
    }
--- response_body
a.test 200 MISS
b.test 200 HIT
