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
        add_eligible_route = function(id, uri)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/' .. id,
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "]] .. uri .. [["
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
        end

        add_ineligible_route = function(id, uri)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/' .. id,
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1,
                            "127.0.0.1:1981": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "]] .. uri .. [["
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
        end

        update_route_to_ineligible = function(id)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/' .. id .. '/upstream/nodes',
                ngx.HTTP_PATCH,
                [[{
                    "127.0.0.1:1980": 1,
                    "127.0.0.1:1981": 1
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
        end

        update_route_to_eligible = function(id)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/' .. id .. '/upstream/nodes',
                ngx.HTTP_PATCH,
                [[{
                    "127.0.0.1:1980": 1
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
        end

        clear_route = function(id)
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/' .. id, ngx.HTTP_DELETE)
            return code
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

=== TEST 1: enable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            add_eligible_route(1, "/hello")
            local code, body = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route(1) == 200)
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
enable sample upstream



=== TEST 2: enable sample upstream, add ineligible route lead to disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            add_eligible_route(1, "/hello")
            local code, body = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            add_ineligible_route(2, "/hello1")
            local code, body = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route(1) == 200)
            assert(clear_route(2) == 200)
            ngx.say("done")
        }
    }
--- response_body
done
--- grep_error_log eval
qr/enable sample upstream|proxy request to/
--- grep_error_log_out
enable sample upstream
proxy request to



=== TEST 3: enable sample upstream, update route as ineligible lead to disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            add_eligible_route(1, "/hello")
            add_eligible_route(2, "/hello1")
            local code, body = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            update_route_to_ineligible(2)
            local code, body = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route(1) == 200)
            assert(clear_route(2) == 200)
            ngx.say("done")
        }
    }
--- response_body
done
--- grep_error_log eval
qr/enable sample upstream|proxy request to/
--- grep_error_log_out
enable sample upstream
proxy request to



=== TEST 4: enable sample upstream, add eligible route and keep sample upstream as enable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            add_eligible_route(1, "/hello")
            local code, body = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            add_eligible_route(2, "/hello1")
            local code, body = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route(1) == 200)
            assert(clear_route(2) == 200)
            ngx.say("done")
        }
    }
--- response_body
done
--- grep_error_log eval
qr/enable sample upstream/
--- grep_error_log_out
enable sample upstream
enable sample upstream
--- no_error_log eval
qr/proxy request to \S+/



=== TEST 5: enable sample upstream, delete route and keep sample upstream as enable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            add_eligible_route(1, "/hello")
            add_eligible_route(2, "/hello1")

            local code, body = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)
            assert(clear_route(2) == 200)
            local code, body = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route(1) == 200)
            ngx.say("done")
        }
    }
--- response_body
done
--- grep_error_log eval
qr/enable sample upstream/
--- grep_error_log_out
enable sample upstream
enable sample upstream
--- no_error_log eval
qr/proxy request to \S+/



=== TEST 6: enable sample upstream, delete all routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            add_eligible_route(1, "/hello")
            add_eligible_route(2, "/hello1")

            local code, body = t("/hello", ngx.HTTP_GET)
            assert(code == 200)
            assert(clear_route(1) == 200)
            assert(clear_route(2) == 200)
            local code, body = t("/hello", ngx.HTTP_GET)
            assert(code == 404)

            ngx.say("done")
        }
    }
--- response_body
done
--- grep_error_log eval
qr/enable sample upstream/
--- grep_error_log_out
enable sample upstream
--- no_error_log eval
qr/proxy request to \S+/



=== TEST 7: disable sample upstream, add eligible route and keep sample upstream as disable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            add_ineligible_route(1, "/hello")
            local code, body = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            add_ineligible_route(2, "/hello1")
            local code, body = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route(1) == 200)
            assert(clear_route(2) == 200)
            ngx.say("done")
        }
    }
--- response_body
done
--- grep_error_log eval
qr/proxy request to/
--- grep_error_log_out
proxy request to
proxy request to
--- no_error_log
enable sample upstream



=== TEST 8: disable sample upstream, add eligible route and keep disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            add_ineligible_route(1, "/hello")
            local code, body = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            add_eligible_route(2, "/hello1")
            local code, body = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route(1) == 200)
            assert(clear_route(2) == 200)
            ngx.say("done")
        }
    }
--- response_body
done
--- grep_error_log eval
qr/proxy request to/
--- grep_error_log_out
proxy request to
proxy request to
--- no_error_log
enable sample upstream



=== TEST 9: disable sample upstream, delete some ineligible route and keep sample upstream as disable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            add_ineligible_route(1, "/hello")
            add_ineligible_route(2, "/hello1")
            local code, body = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route(2) == 200)
            local code, body = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route(1) == 200)
            ngx.say("done")
        }
    }
--- response_body
done
--- grep_error_log eval
qr/proxy request to/
--- grep_error_log_out
proxy request to
proxy request to
--- no_error_log
enable sample upstream



=== TEST 10: disable sample upstream, update some of ineligible route to eligible, keep sample upstream as disable
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            add_ineligible_route(1, "/hello")
            add_ineligible_route(2, "/hello1")
            local code, body = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            update_route_to_eligible(1)
            local code, body = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route(1) == 200)
            assert(clear_route(2) == 200)
            ngx.say("done")
        }
    }
--- response_body
done
--- grep_error_log eval
qr/proxy request to/
--- grep_error_log_out
proxy request to
proxy request to
--- no_error_log
enable sample upstream



=== TEST 11: disable sample upstream, delete all ineligible route, enable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            add_ineligible_route(1, "/hello")
            add_ineligible_route(2, "/hello1")
            add_eligible_route(3, "/server_port")

            local code, body = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route(1) == 200)
            assert(clear_route(2) == 200)
            local code, body = t("/server_port", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route(3) == 200)
            ngx.say("done")
        }
    }
--- response_body
done
--- grep_error_log eval
qr/enable sample upstream|proxy request to/
--- grep_error_log_out
proxy request to
enable sample upstream



=== TEST 12: disable sample upstream, update all of ineligible route to eligible, enable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            add_ineligible_route(1, "/hello")
            add_ineligible_route(2, "/hello1")
            local code, body = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            update_route_to_eligible(1)
            update_route_to_eligible(2)
            local code, body = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route(1) == 200)
            assert(clear_route(2) == 200)

            ngx.say("done")
        }
    }
--- response_body
done
--- grep_error_log eval
qr/enable sample upstream|proxy request to/
--- grep_error_log_out
proxy request to
enable sample upstream
