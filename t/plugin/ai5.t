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

log_level('info');
worker_connections(256);
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->extra_init_by_lua) {
        my $extra_init_by_lua = <<_EOC_;
        unload_ai_module = function ()
            local t = require("lib.test_admin").test
            local data = [[
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
apisix:
  node_listen: 1984
plugins:
            ]]
            require("lib.test_admin").set_config_yaml(data)

            local code, body = t('/apisix/admin/plugins/reload',
                                    ngx.HTTP_PUT)
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
        end

        load_ai_module = function ()
            local t = require("lib.test_admin").test
            local data = [[
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
apisix:
  node_listen: 1984
plugins:
  - ai
            ]]
            require("lib.test_admin").set_config_yaml(data)

            local code, body = t('/apisix/admin/plugins/reload',
                                    ngx.HTTP_PUT)
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
        end
_EOC_

        $block->set_value("extra_init_by_lua", $extra_init_by_lua);
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: enable(default) -> disable -> enable
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- register route
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
            -- enable route cache
            local code = t('/hello', ngx.HTTP_GET)
            assert(code == 200)

            -- disable ai plugin
            unload_ai_module()

            local code = t('/hello', ngx.HTTP_GET)
            assert(code == 200)

            -- enable ai plugin
            load_ai_module()

            -- TODO: The route cache should be enabled, but since no new routes are registered,
            -- the route tree is not rebuilt,
            -- so it is not possible to switch to route cache mode, we should fix it
            local code = t('/hello', ngx.HTTP_GET)
            assert(code == 200, "enable: access /hello")

            -- register a new route and trigger a route tree rebuild
            local code, body = t('/apisix/admin/routes/2',
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
                    "uri": "/echo"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code = t('/hello', ngx.HTTP_GET)
            assert(code == 200)

            ngx.say("done")
        }
    }
--- response_body
done
--- grep_error_log eval
qr/route match mode: \S[^,]+/
--- grep_error_log_out
route match mode: ai_match
route match mode: radixtree_host_uri
route match mode: radixtree_host_uri
route match mode: radixtree_host_uri
route match mode: ai_match
route match mode: radixtree_host_uri



=== TEST 2: disable(default) -> enable -> disable
--- yaml_config
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
apisix:
  node_listen: 1984
plugins:
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- register route
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

            local code = t('/hello', ngx.HTTP_GET)
            assert(code == 200)

            -- enable ai plugin
            load_ai_module()

            local code = t('/hello', ngx.HTTP_GET)
            assert(code == 200)

            -- register a new route and trigger a route tree rebuild
            local code, body = t('/apisix/admin/routes/2',
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
                    "uri": "/echo"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local code = t('/hello', ngx.HTTP_GET)
            assert(code == 200)

            -- disable ai plugin
            unload_ai_module()

            local code = t('/hello', ngx.HTTP_GET)
            assert(code == 200)

            ngx.say("done")
        }
    }
--- response_body
done
--- grep_error_log eval
qr/route match mode: \S[^,]+/
--- grep_error_log_out
route match mode: radixtree_host_uri
route match mode: radixtree_host_uri
route match mode: ai_match
route match mode: radixtree_host_uri
route match mode: radixtree_host_uri
