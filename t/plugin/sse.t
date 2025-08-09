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
no_shuffle();
log_level('info');

add_block_preprocessor(sub {
    my ($block) = @_;
    
    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
    
    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: add upstream and route for sse plugin test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "nodes": {
                        "127.0.0.1:1980": 1
                    }
                }]]
            )
            
            if code >= 300 then
                ngx.status = code
                return
            end
            
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/sse_test",
                    "plugins": {
                        "sse": {}
                    },
                    "upstream_id": "1"
                }]]
            )
            
            if code >= 300 then
                ngx.status = code
                return
            end
            
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 2: test sse plugin with default configuration
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/sse_test"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
            })
            
            if not res then
                ngx.log(ngx.ERR, "request failed: ", err)
                ngx.status = 500
                return
            end
            
            ngx.status = res.status
            
            -- Check headers
            local content_type = res.headers["Content-Type"]
            local x_accel_buffering = res.headers["X-Accel-Buffering"]
            local cache_control = res.headers["Cache-Control"]
            local connection = res.headers["Connection"]
            
            ngx.say("Status: ", res.status)
            ngx.say("Content-Type: ", content_type or "nil")
            ngx.say("X-Accel-Buffering: ", x_accel_buffering or "nil")
            ngx.say("Cache-Control: ", cache_control or "nil")
            ngx.say("Connection: ", connection or "nil")
        }
    }
--- response_body_like
Status: 200
Content-Type: text/event-stream; charset=utf-8
X-Accel-Buffering: no
Cache-Control: no-cache
Connection: keep-alive



=== TEST 3: test sse plugin with override_content_type = false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/sse_test",
                    "plugins": {
                        "sse": {
                            "override_content_type": false
                        }
                    },
                    "upstream_id": "1"
                }]]
            )
            
            if code >= 300 then
                ngx.status = code
                return
            end
            
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/sse_test"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
            })
            
            if not res then
                ngx.log(ngx.ERR, "request failed: ", err)
                ngx.status = 500
                return
            end
            
            ngx.status = res.status
            
            -- The upstream (port 1980) should return HTML by default
            -- So Content-Type should NOT be text/event-stream
            local content_type = res.headers["Content-Type"]
            local x_accel_buffering = res.headers["X-Accel-Buffering"]
            
            ngx.say("Status: ", res.status)
            ngx.say("Content-Type: ", content_type or "nil")
            ngx.say("X-Accel-Buffering: ", x_accel_buffering or "nil")
        }
    }
--- response_body_like
Status: 200
Content-Type: (?!text/event-stream).*
X-Accel-Buffering: no



=== TEST 4: test sse plugin with custom headers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/sse_test",
                    "plugins": {
                        "sse": {
                            "connection_header": "Upgrade",
                            "cache_control": "public, max-age=3600"
                        }
                    },
                    "upstream_id": "1"
                }]]
            )
            
            if code >= 300 then
                ngx.status = code
                return
            end
            
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/sse_test"
            local res, err = httpc:request_uri(uri, {
                method = "GET",
            })
            
            if not res then
                ngx.log(ngx.ERR, "request failed: ", err)
                ngx.status = 500
                return
            end
            
            ngx.status = res.status
            
            local cache_control = res.headers["Cache-Control"]
            local connection = res.headers["Connection"]
            
            ngx.say("Status: ", res.status)
            ngx.say("Cache-Control: ", cache_control or "nil")
            ngx.say("Connection: ", connection or "nil")
        }
    }
--- response_body_like
Status: 200
Cache-Control: public, max-age=3600
Connection: Upgrade



=== TEST 5: test sse plugin schema validation
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.sse")
            
            -- Test valid config
            local ok, err = plugin.check_schema({})
            if not ok then
                ngx.say("Default schema validation failed: ", err)
                return
            end
            
            -- Test invalid proxy_read_timeout
            local ok, err = plugin.check_schema({
                proxy_read_timeout = -1
            })
            if ok then
                ngx.say("Schema validation should have failed for negative timeout")
                return
            end
            
            -- Test valid zero timeout
            local ok, err = plugin.check_schema({
                proxy_read_timeout = 0
            })
            if not ok then
                ngx.say("Zero timeout validation failed: ", err)
                return
            end
            
            ngx.say("Schema validation tests passed")
        }
    }
--- response_body
Schema validation tests passed



=== TEST 6: cleanup
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            local code, body = t('/apisix/admin/upstreams/1', ngx.HTTP_DELETE)
            ngx.say("passed")
        }
    }
--- response_body
passed