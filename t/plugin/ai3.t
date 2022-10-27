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

            return t('/apisix/admin/plugins/reload',
                                    ngx.HTTP_PUT)
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

            return t('/apisix/admin/plugins/reload',
                                        ngx.HTTP_PUT)
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
            local ai = require("apisix.plugins.ai")
            local router = require("apisix.router")
            local org_match = router.router_http.matching
            local ai_match = ai.route_matching

            local apisix = require("apisix")
            local org_upstream = apisix.handle_upstream
            local ai_upstream = ai.handle_upstream

            local org_balancer_phase = apisix.http_balancer_phase
            local ai_balancer_phase = ai.http_balancer_phase

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
            assert(code == 200, "enable(default): access /hello")
            assert(router.router_http.matching == ai_match, "enable(default): router_http.matching")
            assert(apisix.handle_upstream == ai_upstream, "enable(default): ai_upstream")
            assert(apisix.http_balancer_phase == ai_balancer_phase, "enable(default): http_balancer_phase")

            -- disable ai plugin
            local code = unload_ai_module()
            assert(code == 200, "disable ai plugin")
            ngx.sleep(2)
            local code = t('/hello', ngx.HTTP_GET)
            assert(code == 200, "disable: access /hello")
            assert(router.router_http.matching == org_match, "disable: router_http.matching")
            assert(apisix.handle_upstream == org_upstream, "disable: ai_upstream")
            assert(apisix.http_balancer_phase == org_balancer_phase, "disable: http_balancer_phase")

            -- enable ai plugin
            local code = load_ai_module()
            assert(code == 200, "enable ai plugin")
            ngx.sleep(2)
            local code = t('/hello', ngx.HTTP_GET)
            assert(code == 200, "enable: access /hello")
            -- TODO: It's not very reasonable, we need to fix it
            assert(router.router_http.matching == org_match, "enable: router_http.matching")
            assert(apisix.handle_upstream == org_upstream, "enable: ai_upstream")
            assert(apisix.http_balancer_phase == org_balancer_phase, "enable: http_balancer_phase")

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

            local code = t('/echo', ngx.HTTP_GET)
            assert(code == 200, "register again: access /echo")
            local new_ai = require("apisix.plugins.ai")
            assert(router.router_http.matching == new_ai.route_matching, "enable(after require): router_http.matching")
            assert(apisix.handle_upstream == new_ai.handle_upstream, "enable(after require): handle_upstream")
            assert(apisix.http_balancer_phase == new_ai.http_balancer_phase, "enable(after require): http_balancer_phase")
        }
    }



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
            local router = require("apisix.router")
            local org_match = router.router_http.matching
            local apisix = require("apisix")
            local org_upstream = apisix.handle_upstream
            local org_balancer_phase = apisix.http_balancer_phase

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
            assert(code == 200, "disable(default): access /hello")
            assert(router.router_http.matching == org_match, "disable(default): router_http.matching")
            assert(apisix.handle_upstream == org_upstream, "disable(default): handle_upstream")
            assert(apisix.http_balancer_phase == org_balancer_phase, "disable(default): http_balancer_phase")

            -- enable ai plugin
            local code = load_ai_module()
            assert(code == 200, "enable ai plugin")
            ngx.sleep(2)
            local code = t('/hello', ngx.HTTP_GET)
            assert(code == 200, "enable: access /hello")
            -- TODO: It's not very reasonable, we need to fix it
            assert(router.router_http.matching == org_match, "enable: router_http.matching")
            assert(apisix.handle_upstream == org_upstream, "enable: handle_upstream")
            assert(apisix.http_balancer_phase == org_balancer_phase, "enable: http_balancer_phase")

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

            local code = t('/echo', ngx.HTTP_GET)
            assert(code == 200, "register again: access /echo")
            local ai = require("apisix.plugins.ai")
            assert(router.router_http.matching == ai.route_matching, "enable(after require): router_http.matching")
            assert(apisix.handle_upstream == ai.handle_upstream, "enable(after require): handle_upstream")
            assert(apisix.http_balancer_phase == ai.http_balancer_phase, "enable(after require): http_balancer_phase")

            -- disable ai plugin
            local code = unload_ai_module()
            assert(code == 200, "unload ai plugin")
            ngx.sleep(2)
            local code = t('/hello', ngx.HTTP_GET)
            assert(code == 200, "disable: access /hello")
            assert(router.router_http.matching == org_match, "disable: router_http.matching")
            assert(apisix.handle_upstream == org_upstream, "disable: handle_upstream")
            assert(apisix.http_balancer_phase == org_balancer_phase, "disable: http_balancer_phase")
        }
    }
