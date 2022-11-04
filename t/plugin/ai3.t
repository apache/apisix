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

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: keep priority behavior consistent
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "priority": 1,
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/server_port"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "priority": 10,
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1981": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/server_port"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end


            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/server_port"
            local t = {}
            for i = 1, 2 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri)
                    assert(res.status == 200)
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                    ngx.say(res.body)
                end, i))
                table.insert(t, th)
            end
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
            end
        }
    }
--- response_body
1981
1981
--- error_log
use ai plane to match route



=== TEST 2: keep route cache as latest data
# update the attributes that do not participate in the route cache key to ensure
# that the route cache use the latest data
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/pm',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "public-api": {}
                    },
                    "uri": "/apisix/prometheus/metrics"
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
                    "name": "foo",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "prometheus": {
                            "prefer_name": true
                        }
                    },
                    "uri": "/hello"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri)
            assert(res.status == 200)
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            local metrics_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics"
            local httpc = http.new()
            local res, err = httpc:request_uri(metrics_uri)
            assert(res.status == 200)
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            local m, err = ngx.re.match(res.body, "apisix_bandwidth{type=\"ingress\",route=\"foo\"", "jo")
            ngx.say(m[0])

            -- update name by patch
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PATCH,
                [[{
                    "name": "bar"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri)
            assert(res.status == 200)
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            local metrics_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/apisix/prometheus/metrics"
            local httpc = http.new()
            local res, err = httpc:request_uri(metrics_uri)
            assert(res.status == 200)
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end
            local m, err = ngx.re.match(res.body, "apisix_bandwidth{type=\"ingress\",route=\"bar\"", "jo")
            ngx.say(m[0])
        }
    }
--- response_body
apisix_bandwidth{type="ingress",route="foo"
apisix_bandwidth{type="ingress",route="bar"



==== TEST 3: route has filter_func, disable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "filter_func": "function(vars) return vars.arg_k ~= 'v' end",
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
                ngx.say(body)
                return
            end

            local code = t('/hello??k=a', ngx.HTTP_GET)
            ngx.say(code)

            local code = t('/hello??k=v', ngx.HTTP_GET)
            ngx.say(code)
        }
    }
--- response_body
200
404
--- no_error_log
use ai plane to match route
