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

=== TEST 1: enable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
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

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
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
                end, i))
                table.insert(t, th)
            end
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
use ai plane to match route



=== TEST 2: route has vars, disable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "vars": [ ["arg_k", "~=", "v"] ],
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



=== TEST 3: method changed, create different route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
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

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local t = {}
            for i = 1, 4 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err
                    if i % 2 == 0 then
                        res, err = httpc:request_uri(uri, { method = "POST" })
                    else
                        res, err = httpc:request_uri(uri)
                    end
                    assert(res.status == 200)
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end, i))
                table.insert(t, th)
            end
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
use ai plane to match route



=== TEST 4: route with plugins, enable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{

                    "plugins": {
                        "limit-count": {
                            "count": 9999,
                            "time_window": 60
                        }
                    },
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

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
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
                end, i))
                table.insert(t, th)
            end
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
use ai plane to match route



=== TEST 5: enable -> disable -> enable -> disable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local uri2 = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1?k=a"
            local uri3 = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1?k=v"

            -- round 1: all routes without vars or filter_fun, enable route cache
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
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
            ngx.sleep(0.5)

            local threads1 = {}
            for i = 1, 2 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri)
                    assert(res.status == 200)
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end, i))
                table.insert(threads1, th)
            end

            for i, th in ipairs(threads1) do
                ngx.thread.wait(th)
            end

            -- round 2: routes with vars or filter_fun, disable route cache
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "vars": [ ["arg_k", "~=", "v"] ],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello1"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local threads2 = {}
            for i = 1, 2 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err
                    if i == 1 then
                        -- arg_k = a, match route 2
                        res, err = httpc:request_uri(uri2)
                        assert(res.status == 200)
                    else
                        -- arg_k = v, not match route 2
                        res, err = httpc:request_uri(uri3)
                        assert(res.status == 404)
                    end
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end, i))
                table.insert(threads2, th)
            end

            for i, th in ipairs(threads2) do
                ngx.thread.wait(th)
            end

           -- round 3: delete route with vars, the remaining route
           -- has no vars or filter_fun, enable route cache
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_DELETE)

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local threads3 = {}
            for i = 1, 2 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri)
                    assert(res.status == 200)
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end, i))
                table.insert(threads3, th)
            end

            for i, th in ipairs(threads3) do
                ngx.thread.wait(th)
            end

            -- round 4: routes with vars or filter_fun, disable route cache
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "vars": [ ["arg_k", "~=", "v"] ],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello1"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local threads4 = {}
            for i = 1, 2 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err
                    if i == 1 then
                        -- arg_k = a, match route 2
                        res, err = httpc:request_uri(uri2)
                        assert(res.status == 200)
                    else
                        -- arg_k = v, not match route 2
                        res, err = httpc:request_uri(uri3)
                        assert(res.status == 404)
                    end
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end, i))
                table.insert(threads4, th)
            end

            for i, th in ipairs(threads4) do
                ngx.thread.wait(th)
            end

            -- clean route 2
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_DELETE)

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
--- grep_error_log eval
qr/use ai plane to match route/
--- grep_error_log_out
use ai plane to match route
use ai plane to match route



=== TEST 6: route key: uri
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
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
            ngx.sleep(1)

            for i = 1, 2 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                assert(res.status == 200)
                if not res then
                    ngx.log(ngx.ERR, err)
                    return
                end
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
route cache key: /hello



=== TEST 7: route key: uri + method
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
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
            ngx.sleep(1)

            for i = 1, 2 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                assert(res.status == 200)
                if not res then
                    ngx.log(ngx.ERR, err)
                    return
                end
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
route cache key: /hello#GET



=== TEST 8: route key: uri + method + host
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "host": "127.0.0.1",
                    "methods": ["GET"],
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
            ngx.sleep(1)

            for i = 1, 2 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri)
                assert(res.status == 200)
                if not res then
                    ngx.log(ngx.ERR, err)
                    return
                end
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
route cache key: /hello#GET#127.0.0.1



=== TEST 9: enable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
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
            ngx.sleep(0.5)
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri)
            assert(res.status == 200)
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
enable sample upstream



=== TEST 10: route has plugins and run before_proxy, disable samply upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "before_proxy",
                            "functions" : ["return function(conf, ctx) ngx.log(ngx.WARN, \"run before_proxy phase balancer_ip : \", ctx.balancer_ip) end"]
                        }
                    },
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
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri)
            assert(res.status == 200)
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
run before_proxy phase balancer_ip : 127.0.0.1
--- no_error_log
enable sample upstream



=== TEST 11: upstream has more than one nodes, disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1981": 1
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
            ngx.sleep(0.5)
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri)
            assert(res.status == 200)
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say("done")
        }
    }
--- response_body
done
--- no_error_log
enable sample upstream



=== TEST 12: node has domain, disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "admin.apisix.dev:1980": 1
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
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri)
            assert(res.status == 200)
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say("done")
        }
    }
--- response_body
done
--- no_error_log
enable sample upstream



=== TEST 13: enable --> disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
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
            ngx.sleep(0.5)

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri)
            assert(res.status == 200)
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "enable_websocket": true,
                    "uri": "/hello"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri)
            assert(res.status == 200)
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- grep_error_log eval
qr/enable sample upstream/
--- grep_error_log_out
enable sample upstream



=== TEST 14: renew route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            for k = 1, 2 do
                local code, body = t('/apisix/admin/routes/' .. k,
                     ngx.HTTP_PUT,
                     [[{
                        "host": "127.0.0.1",
                        "methods": ["GET"],
                        "plugins": {
                            "proxy-rewrite": {
                                "uri": "/hello"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello]] .. k .. [["
                    }]]
                )
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
                ngx.sleep(1)
                for i = 1, 2 do
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri .. k)
                    assert(res.status == 200)
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end
            end
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
renew route cache: count=3001
renew route cache: count=3002
