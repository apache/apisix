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
use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

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

    if (!defined $block->extra_init_by_lua) {
        my $extra_init_by_lua = <<_EOC_;
            local apisix = require("apisix")
            apisix.http_header_filter_phase = function ()
                ngx.header.content_length = 14
            end

            apisix.http_body_filter_phase = function ()
                ngx.arg[1] = "do body filter"
            end
_EOC_

        $block->set_value("extra_init_by_lua", $extra_init_by_lua);
    }
});

run_tests();

__DATA__

=== TEST 1: enable skip body filter
--- extra_init_by_lua
    local apisix = require("apisix")
    apisix.http_header_filter_phase = function ()
        ngx.header.content_length = nil
    end

    apisix.http_body_filter_phase = function ()
        ngx.arg[1] = "do body filter"
    end
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
            ngx.print(res.body)
        }
    }
--- response_body
hello world



=== TEST 2: route with plugin_config_id, disable skip body filter
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_configs/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "before_proxy",
                            "functions" : ["return function(conf, ctx) ngx.log(ngx.WARN, \"run before_proxy phase balancer_ip : \", ctx.balancer_ip) end"]
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugin_config_id": "1",
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
            ngx.say(res.body)
        }
    }
--- response_body
do body filter
--- error_log
run before_proxy phase balancer_ip : 127.0.0.1
--- no_error_log
enable sample upstream



=== TEST 3: route with plugins, disable skip body filter
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "new_consumer",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-jack"
                        },
                        "serverless-pre-function": {
                            "phase": "before_proxy",
                            "functions" : ["return function(conf, ctx) ngx.log(ngx.WARN, \"run before_proxy phase balancer_ip : \", ctx.balancer_ip) end"]
                        }
                    }
                }]]
            )
            ngx.sleep(0.5)

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "key-auth": {}
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
            ngx.sleep(0.5)

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local headers = {
                ["apikey"] = "auth-jack"
            }
            local res, err = httpc:request_uri(uri, {headers = headers})
            assert(res.status == 200)
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say(res.body)
        }
    }
--- response_body
do body filter
--- error_log
run before_proxy phase balancer_ip : 127.0.0.1
--- no_error_log
enable sample upstream



=== TEST 4: one of route has plugins, disable skip body filter
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
            ngx.sleep(0.5)

            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
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

            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1"
            local httpc = http.new()
            local headers = {
                ["apikey"] = "auth-jack"
            }
            local res, err = httpc:request_uri(uri, {headers = headers})
            assert(res.status == 200)
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say(res.body)
        }
    }
--- response_body
do body filter
--- no_error_log
enable sample upstream



=== TEST 5: exist global_rules, disable skip body filter
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "phase": "before_proxy",
                            "functions" : ["return function(conf, ctx) ngx.log(ngx.WARN, \"run before_proxy phase balancer_ip : \", ctx.balancer_ip) end"]
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.sleep(0.5)

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
            ngx.say(res.body)
        }
    }
--- response_body
do body filter
--- error_log
run before_proxy phase balancer_ip : 127.0.0.1
--- no_error_log
enable sample upstream



=== TEST 6: upstream with keepalive_pool, disable sample upstream
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
                        "keepalive_pool": {
                            "size": 1,
                            "idle_timeout": 8,
                            "requests": 2
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
            ngx.say(res.body)
        }
    }
--- response_body
do body filter
--- error_log
proxy request to 127.0.0.1:1980
--- no_error_log
enable sample upstream
