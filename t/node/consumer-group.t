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
log_level('warn');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: consumer group usage
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, err = t('/apisix/admin/consumer_groups/bar',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "response-rewrite": {
                            "body": "hello"
                        }
                    }
                }]]
            )
            if code > 300 then
                ngx.log(ngx.ERR, err)
                return
            end

            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "group_id": "bar",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "bar"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, err = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "basic-auth": {}
                    }
                }]]
            )
            if code > 300 then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.sleep(0.5)

            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local headers = {
                ["Authorization"] = "Basic Zm9vOmJhcg=="
            }
            local res, err = httpc:request_uri(uri, {headers = headers})
            ngx.say(res.body)

            local code, err = t('/apisix/admin/consumer_groups/bar',
                ngx.HTTP_PATCH,
                [[{
                    "plugins": {
                        "response-rewrite": {
                            "body": "world"
                        }
                    }
                }]]
            )
            if code > 300 then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.sleep(0.1)

            local res, err = httpc:request_uri(uri, {headers = headers})
            ngx.say(res.body)
        }
    }
--- response_body
hello
world



=== TEST 2: validated plugins configuration via incremental sync (malformed data)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local core = require("apisix.core")

            assert(core.etcd.set("/consumer_groups/bar",
                {id = "bar", plugins = { ["uri-blocker"] = { block_rules =  1 }}}
            ))
            -- wait for sync
            ngx.sleep(0.6)

            assert(core.etcd.delete("/consumer_groups/bar"))
        }
    }
--- error_log
property "block_rules" validation failed



=== TEST 3: don't override the plugin in the consumer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, err = t('/apisix/admin/consumer_groups/bar',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "response-rewrite": {
                            "body": "hello"
                        }
                    }
                }]]
            )
            if code > 300 then
                ngx.log(ngx.ERR, err)
                return
            end

            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "group_id": "bar",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "bar"
                        },
                        "response-rewrite": {
                            "body": "world"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, err = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "basic-auth": {}
                    }
                }]]
            )
            if code > 300 then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.sleep(0.1)

            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local headers = {
                ["Authorization"] = "Basic Zm9vOmJhcg=="
            }
            local res, err = httpc:request_uri(uri, {headers = headers})
            ngx.say(res.body)
        }
    }
--- response_body
world



=== TEST 4: check consumer_group_id var
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, err = t('/apisix/admin/consumer_groups/bar',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-post-function": {
                            "phase": "access",
                            "functions" : ["return function(_, ctx) ngx.say(ctx.var.consumer_group_id); ngx.exit(200); end"]
                        }
                    }
                }]]
            )
            if code > 300 then
                ngx.log(ngx.ERR, err)
                return
            end

            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "foo",
                    "group_id": "bar",
                    "plugins": {
                        "basic-auth": {
                            "username": "foo",
                            "password": "bar"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code, err = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "basic-auth": {}
                    }
                }]]
            )
            if code > 300 then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.sleep(0.5)

            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local headers = {
                ["Authorization"] = "Basic Zm9vOmJhcg=="
            }
            local res, err = httpc:request_uri(uri, {headers = headers})
            ngx.print(res.body)
        }
    }
--- response_body
bar
