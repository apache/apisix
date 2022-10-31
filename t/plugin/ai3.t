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
        update_route = function(id, data)
            local cjson = require("cjson")
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/'..id, ngx.HTTP_PUT, cjson.encode(data))
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
        end

        enable_ai_route_match = function ()
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello",
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }
            local id = "1"
            update_route(id, data)

            local code = t("/hello", ngx.HTTP_GET)
            assert(code == 200, "enable ai route match")

            return id
        end

        disable_ai_route_match = function ()
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello1",
                vars = {
                    {"arg_k", "==", "v"}
                },
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type =  "roundrobin"
                }
            }
            local id = "2"
            update_route(id, data)

            local code = t("/hello1?k=v", ngx.HTTP_GET)
            assert(code == 200, "enable ai route match")

            return id
        end

        clear_route = function(id)
            local t = require("lib.test_admin").test

            local code = t('/apisix/admin/routes/' .. id, ngx.HTTP_DELETE)
            return code
        end
_EOC_

        $block->set_value("extra_init_by_lua", $extra_init_by_lua);
    }

    if (!defined $block->config) {
        my $default_config = <<_EOC_;
            location /t {
                content_by_lua_block {
                    local t = require("lib.test_admin").test

                    enable_ai_route_match()

                    ngx.say("done")
                }
            }
_EOC_

        $block->set_value("config", $default_config);
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

=== TEST 1: enable route cache
--- response_body
done



=== TEST 2: add r2 with vars, disable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            disable_ai_route_match()

            local code = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
            assert(clear_route("2") == 200)
        }
    }
--- grep_error_log eval
qr/use \S+ plane to match route|route match mode: \S[^,]+/
--- grep_error_log_out
use origin plane to match route
route match mode: radixtree_uri
route match mode: radixtree_uri



=== TEST 3: enable route cache
--- response_body
done



=== TEST 4: update r1 without vars, disable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello",
                vars = {
                    {"arg_k", "==", "v"}
                },
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }

            update_route("1", data)

            local code = t("/hello?k=v", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
        }
    }
--- grep_error_log eval
qr/use \S+ plane to match route|route match mode: \S[^,]+/
--- grep_error_log_out
use origin plane to match route
route match mode: radixtree_uri



=== TEST 5: enable route cache
--- response_body
done



=== TEST 6: add r2, enable route cache still
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello1",
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }

            update_route("2", data)
            -- route change, rebuild lrucache
            local code = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            -- miss cache
            local code = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
            assert(clear_route("2") == 200)
        }
    }
--- grep_error_log eval
qr/renew route cache: count=\d+|route match mode: ai_match|route cache key: \S[^,]+/
--- grep_error_log_out
renew route cache: count=3002
route match mode: ai_match
route cache key: /hello#GET
route match mode: ai_match
route cache key: /hello1#GET



=== TEST 7: enable route cache
--- response_body
done



=== TEST 8: update upstream uri, enable route cache still and route update successfully
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello1",
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }

            update_route("1", data)
            -- route change, rebuild lrucache
            local code = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            local code = t("/hello", ngx.HTTP_GET)
            assert(code == 404)

            assert(clear_route("1") == 200)
        }
    }
--- grep_error_log eval
qr/renew route cache: count=\d+|route match mode: ai_match|route cache key: \S[^,]+/
--- grep_error_log_out
renew route cache: count=3001
route match mode: ai_match
route cache key: /hello1#GET
route match mode: ai_match
route cache key: /hello#GET



=== TEST 9: enable route cache, add r2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            enable_ai_route_match()

            local data = {
                methods = {"GET"},
                uri = "/hello1",
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }

            update_route("2", data)

            local code = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 10: delete r1, enable route cache still
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            assert(clear_route("1") == 200)
            local code = t("/hello", ngx.HTTP_GET)
            assert(code == 404)
            local code = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)
        }
    }
--- grep_error_log eval
qr/route match mode: ai_match/
--- grep_error_log_out
route match mode: ai_match
route match mode: ai_match



=== TEST 11: delete r2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            assert(clear_route("2") == 200)

            local code = t("/hello", ngx.HTTP_GET)
            assert(code == 404)
            local code = t("/hello1", ngx.HTTP_GET)
            assert(code == 404)
        }
    }
--- grep_error_log eval
qr/route match mode: ai_match/
--- grep_error_log_out
route match mode: ai_match
route match mode: ai_match



=== TEST 12: disable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            disable_ai_route_match()

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 13: add r1 with vars, disable route cache still
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello",
                vars = {
                    {"arg_k", "==", "s"}
                },
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }

            update_route("1", data)

            local code = t("/hello?k=s", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
            assert(clear_route("2") == 200)
        }
    }
--- grep_error_log eval
qr/use \S+ plane to match route|route match mode: \S[^,]+/
--- grep_error_log_out
use origin plane to match route
route match mode: radixtree_uri
--- no_error_log
route match mode: ai_match



=== TEST 14: disable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            disable_ai_route_match()

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 15: add r1 without vars, disable route cache still
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello",
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }

            update_route("1", data)

            local code = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
            assert(clear_route("2") == 200)
        }
    }
--- grep_error_log eval
qr/use \S+ plane to match route|route match mode: \S[^,]+/
--- grep_error_log_out
use origin plane to match route
route match mode: radixtree_uri
--- no_error_log
route match mode: ai_match



=== TEST 16: disable route cache, add r1 with vars
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            disable_ai_route_match()

            local data = {
                methods = {"GET"},
                uri = "/hello",
                vars = {
                    {"arg_k", "==", "s"}
                },
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }

            update_route("1", data)

            local code = t("/hello?k=s", ngx.HTTP_GET)
            assert(code == 200)

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 17: update r1 without vars, disable route cache still
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello",
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }

            update_route("1", data)

            local code = t("/hello", ngx.HTTP_GET)
            assert(code == 200)
        }
    }
--- grep_error_log eval
qr/use \S+ plane to match route|route match mode: \S[^,]+/
--- grep_error_log_out
use origin plane to match route
route match mode: radixtree_uri
--- no_error_log
route match mode: ai_match



=== TEST 18: update r2 without vars, enable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello1",
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }

            update_route("2", data)

            local code = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
            assert(clear_route("2") == 200)
        }
    }
--- grep_error_log eval
qr/use \S+ plane to match route|route match mode: \S[^,]+/
--- grep_error_log_out
use ai plane to match route
route match mode: ai_match
route match mode: radixtree_uri



=== TEST 19: disable route cache, add r1 with vars, add r3 without vars
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            disable_ai_route_match()

            local data = {
                methods = {"GET"},
                uri = "/hello",
                vars = {
                    {"arg_k", "==", "s"}
                },
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }
            update_route("1", data)
            local code = t("/hello?k=s", ngx.HTTP_GET)
            assert(code == 200)

            local data = {
                methods = {"GET"},
                uri = "/echo",
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }
            update_route("3", data)
            local code = t("/echo", ngx.HTTP_GET)
            assert(code == 200)

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 20: delete r1, disable route cache still
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            assert(clear_route("1") == 200)

            local code = t("/hello?k=s", ngx.HTTP_GET)
            assert(code == 404)
            local code = t("/hello1?k=v", ngx.HTTP_GET)
            assert(code == 200)
        }
    }
--- grep_error_log eval
qr/use \S+ plane to match route|route match mode: \S[^,]+/
--- grep_error_log_out
use origin plane to match route
route match mode: radixtree_uri
route match mode: radixtree_uri
--- no_error_log
route match mode: ai_match



=== TEST 21: delete r2, enable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            assert(clear_route("2") == 200)

            local code = t("/hello?k=s", ngx.HTTP_GET)
            assert(code == 404)
            local code = t("/hello1?k=v", ngx.HTTP_GET)
            assert(code == 404)
            local code = t("/echo", ngx.HTTP_GET)
            assert(code == 200)
        }
    }
--- grep_error_log eval
qr/use \S+ plane to match route|route match mode: ai_match|route cache key: \S[^,]+/
--- grep_error_log_out
use ai plane to match route
route match mode: ai_match
route cache key: /hello#GET
route match mode: ai_match
route cache key: /hello1#GET
route match mode: ai_match
route cache key: /echo#GET



=== TEST 22: delete r2, enable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            assert(clear_route("3") == 200)

            local code = t("/hello?k=s", ngx.HTTP_GET)
            assert(code == 404)
            local code = t("/hello1?k=v", ngx.HTTP_GET)
            assert(code == 404)
            local code = t("/echo", ngx.HTTP_GET)
            assert(code == 404)

            ngx.say("ok")
        }
    }
--- response_body
ok



=== TEST 23: enable route cache
--- response_body
done



=== TEST 24: update r1 with remote_addr, disable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello",
                remote_addrs = {"127.0.0.1"},
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }

            update_route("1", data)

            local code = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
        }
    }
--- error_log
use origin plane to match route
route match mode: radixtree_uri
--- no_error_log
use ai plane to match route
route match mode: ai_match



=== TEST 25: enable route cache
--- response_body
done



=== TEST 26: add r2 with remote_addr, disable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello1",
                remote_addrs = {"127.0.0.1"},
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }

            update_route("2", data)

            local code = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
            assert(clear_route("2") == 200)
        }
    }
--- error_log
use origin plane to match route
route match mode: radixtree_uri
--- no_error_log
use ai plane to match route
route match mode: ai_match



=== TEST 27: enable route cache, add service
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test

        enable_ai_route_match()

        local data = {
            upstream = {
                nodes = {
                    ["127.0.0.1:1980"] = 1
                },
                type = "roundrobin"
            }
        }
        local json = require("cjson")
        local code, body = t('/apisix/admin/services/1',ngx.HTTP_PUT, json.encode(data))
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



=== TEST 28: update r1 with service_id, disable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello",
                service_id = 1
            }

            update_route("1", data)

            local code = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
        }
    }
--- error_log
use origin plane to match route
route match mode: radixtree_uri
--- no_error_log
use ai plane to match route
route match mode: ai_match



=== TEST 29: enable route cache
--- response_body
done



=== TEST 30: add r2 with service_id, disable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello1",
                service_id = 1
            }

            update_route("2", data)

            local code = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
            assert(clear_route("2") == 200)
        }
    }
--- error_log
use origin plane to match route
route match mode: radixtree_uri
--- no_error_log
use ai plane to match route
route match mode: ai_match



=== TEST 31: enable route cache, add plugin_configs
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test

        enable_ai_route_match()

        local data = {
            plugins = {
                ["fault-injection"] = {
                    abort = {
                        http_status = 200
                    }
                }
            }
        }
        local json = require("cjson")
        local code, body = t('/apisix/admin/plugin_configs/1',ngx.HTTP_PUT, json.encode(data))
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



=== TEST 32: update r1 with plugin_config_id, disable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello",
                plugin_config_id = 1,
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }

            update_route("1", data)

            local code = t("/hello", ngx.HTTP_GET)
            assert(code == 200, "tt code")

            assert(clear_route("1") == 200)
        }
    }
--- error_log
use origin plane to match route
route match mode: radixtree_uri
--- no_error_log
use ai plane to match route
route match mode: ai_match



=== TEST 33: enable route cache
--- response_body
done



=== TEST 34: add r2 with plugin_config_id, disable route cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello1",
                plugin_config_id = 1,
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }

            update_route("2", data)

            local code = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
            assert(clear_route("2") == 200)
        }
    }
--- error_log
use origin plane to match route
route match mode: radixtree_uri
--- no_error_log
use ai plane to match route
route match mode: ai_match
