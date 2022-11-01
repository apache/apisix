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
                ngx.log(ngx.WARN, body)
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

=== TEST 1: enable sample upstream
--- response_body
done



=== TEST 2: update r1 with script, disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello",
                script = "local _M = {} \n function _M.access(api_ctx) \n ngx.log(ngx.INFO,\"hit access phase\") \n end \nreturn _M",
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
hit access phase
proxy request to 127.0.0.1:1980
--- no_error_log
enable sample upstream



=== TEST 3: enable sample upstream
--- response_body
done



=== TEST 4: add r2 with script, disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello1",
                script = "local _M = {} \n function _M.access(api_ctx) \n ngx.log(ngx.INFO,\"hit access phase\") \n end \nreturn _M",
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
hit access phase
proxy request to 127.0.0.1:1980
--- no_error_log
enable sample upstream



=== TEST 5: enable sample upstream, add service
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



=== TEST 6: update r1 with service_id, disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/echo",
                service_id = 1
            }

            update_route("1", data)

            local code = t("/echo", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
        }
    }
--- error_log
proxy request to 127.0.0.1:1980
--- no_error_log
enable sample upstream



=== TEST 7: enable sample upstream
--- response_body
done



=== TEST 8: add r2 with service_id, disable sample upstream
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
proxy request to 127.0.0.1:1980
--- no_error_log
enable sample upstream



=== TEST 9: enable sample upstream, add plugin_configs
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



=== TEST 10: update r1 with plugin_config_id, disable sample upstream
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
                        ["127.0.0.1:8888"] = 1
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
--- no_error_log
enable sample upstream



=== TEST 11: enable sample upstream
--- response_body
done



=== TEST 12: add r2 with plugin_config_id, disable sample upstream
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
                        ["127.0.0.1:888"] = 1
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
--- no_error_log
enable sample upstream



=== TEST 13: enable sample upstream
--- response_body
done



=== TEST 14: update r1 with plugins, disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello",
                plugins = {
                    ["fault-injection"] = {
                        abort = {
                            http_status = 200
                        }
                    }
                }
            }

            update_route("1", data)

            local code = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
        }
    }
--- no_error_log
enable sample upstream


=== TEST 15: enable sample upstream
--- response_body
done



=== TEST 16: add r2 with plugins, disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local data = {
                methods = {"GET"},
                uri = "/hello1",
                plugins = {
                    ["fault-injection"] = {
                        abort = {
                            http_status = 200
                        }
                    }
                }
            }

            update_route("2", data)

            local code = t("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
            assert(clear_route("2") == 200)
        }
    }
--- no_error_log
enable sample upstream



=== TEST 17: enable sample upstream
--- response_body
done



=== TEST 18: update r1 with domain, disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello",
                upstream = {
                    nodes = {
                        ["localhost:1980"] = 1
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
--- no_error_log
enable sample upstream



=== TEST 19: enable sample upstream
--- response_body
done



=== TEST 20: add r2 with domain, disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local data = {
                methods = {"GET"},
                uri = "/hello1",
                upstream = {
                    nodes = {
                        ["localhost:1980"] = 1
                    },
                    type = "roundrobin"
                }
            }

            update_route("2", data)

            local code = t("/hello1", ngx.HTTP_GET)
            assert(code == 200, "sss")

            assert(clear_route("1") == 200)
            assert(clear_route("2") == 200)
        }
    }
--- no_error_log
enable sample upstream



=== TEST 21: enable sample upstream
--- response_body
done



=== TEST 22: update r1 with pass_host（pass）, disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/uri",
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin",
                    pass_host = "pass"
                }
            }

            update_route("1", data)

            local code = t("/uri", ngx.HTTP_GET)
            assert(code == 200)
        }
    }
--- error_log
enable sample upstream



=== TEST 23: update r1 with pass_host（rewrite）, disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/uri",
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin",
                    pass_host = "rewrite",
                    upstream_host = "test.com"
                }
            }

            update_route("1", data)

            local code = t("/uri", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
        }
    }
--- no_error_log
enable sample upstream



=== TEST 24: enable sample upstream
--- response_body
done



=== TEST 25: add r2 with pass_host(rewrite), disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local data = {
                methods = {"GET"},
                uri = "/hello1",
                upstream = {
                    nodes = {
                        ["localhost:1980"] = 1
                    },
                    type = "roundrobin",
                    pass_host = "rewrite",
                    upstream_host = "test.com"
                }
            }

            update_route("2", data)

            local code = t("/hello1", ngx.HTTP_GET)
            assert(code == 200, "sss")

            assert(clear_route("1") == 200)
            assert(clear_route("2") == 200)
        }
    }
--- no_error_log
enable sample upstream



=== TEST 26: enable sample upstream
--- response_body
done



=== TEST 27: update r1 with scheme, disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello",
                upstream = {
                    nodes = {
                        ["127.0.0.1:1983"] = 1
                    },
                    type = "roundrobin",
                    scheme = "https"
                }
            }

            update_route("1", data)

            local code = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
        }
    }
--- no_error_log
enable sample upstream



=== TEST 28: enable sample upstream
--- response_body
done



=== TEST 29: add r2 with scheme(https), disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local data = {
                methods = {"GET"},
                uri = "/hello1",
                upstream = {
                    nodes = {
                        ["127.0.0.1:1983"] = 1
                    },
                    type = "roundrobin",
                    scheme = "https"
                }
            }

            update_route("2", data)

            local code = t("/hello1", ngx.HTTP_GET)
            assert(code == 200, "sss")

            assert(clear_route("1") == 200)
            assert(clear_route("2") == 200)
        }
    }
--- no_error_log
enable sample upstream



=== TEST 30: enable sample upstream
--- response_body
done



=== TEST 31: update r1 with checks, disable sample upstream
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
                    type = "roundrobin",
                    checks = {
                        active = {
                            http_path = "/status",
                            host = "test.com",
                            healthy = {
                                interval = 2,
                                successes = 1
                            }
                        }
                    }
                }
            }

            update_route("1", data)

            local code = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
        }
    }
--- no_error_log
enable sample upstream



=== TEST 32: enable sample upstream
--- response_body
done



=== TEST 33: add r2 with scheme(https), disable sample upstream
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
                    type = "roundrobin",
                    checks = {
                        active = {
                            http_path = "/status",
                            host = "test.com",
                            healthy = {
                                interval = 2,
                                successes = 1
                            }
                        }
                    }
                }
            }

            update_route("2", data)

            local code = t("/hello1", ngx.HTTP_GET)
            assert(code == 200, "sss")

            assert(clear_route("1") == 200)
            assert(clear_route("2") == 200)
        }
    }
--- no_error_log
enable sample upstream



=== TEST 34: enable sample upstream
--- response_body
done



=== TEST 35: update r1 with retries, disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello",
                upstream = {
                    nodes = {
                        ["127.0.0.1:888"] = 1,
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin",
                    retries = 1
                }
            }

            update_route("1", data)

            local code = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
        }
    }
--- no_error_log
enable sample upstream



=== TEST 36: enable sample upstream
--- response_body
done



=== TEST 37: add r2 with retries, disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local data = {
                methods = {"GET"},
                uri = "/hello1",
                upstream = {
                    nodes = {
                        ["127.0.0.1:888"] = 1,
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin",
                    retries = 1
                }
            }

            update_route("2", data)

            local code = t("/hello1", ngx.HTTP_GET)
            assert(code == 200, "sss")

            assert(clear_route("1") == 200)
            assert(clear_route("2") == 200)
        }
    }
--- no_error_log
enable sample upstream



=== TEST 38: enable sample upstream
--- response_body
done



=== TEST 39: update r1 with timeout, disable sample upstream
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
                    type = "roundrobin",
                    timeout = {
                        connect = 3,
                        read = 3,
                        send = 3
                    }
                }
            }

            update_route("1", data)

            local code = t("/hello", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
        }
    }
--- no_error_log
enable sample upstream



=== TEST 40: enable sample upstream
--- response_body
done



=== TEST 41: add r2 with timeout, disable sample upstream
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
                    type = "roundrobin",
                    timeout = {
                        connect = 3,
                        read = 3,
                        send = 3
                    }
                }
            }

            update_route("2", data)

            local code = t("/hello1", ngx.HTTP_GET)
            assert(code == 200, "sss")

            assert(clear_route("1") == 200)
            assert(clear_route("2") == 200)
        }
    }
--- no_error_log
enable sample upstream



=== TEST 42: enable sample upstream
--- response_body
done



=== TEST 43: update r1 with tls, disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/mtls_client.crt")
            local ssl_key = t.read_file("t/certs/mtls_client.key")

            local data = {
                methods = {"GET"},
                uri = "/hello",
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin",
                    tls = {
                        client_cert = ssl_cert,
                        client_key = ssl_key
                    }
                }
            }

            update_route("1", data)

            local code = t.test("/hello", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
        }
    }
--- no_error_log
enable sample upstream



=== TEST 44: enable sample upstream
--- response_body
done



=== TEST 45: add r2 with tls, disable sample upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/mtls_client.crt")
            local ssl_key = t.read_file("t/certs/mtls_client.key")

            local data = {
                methods = {"GET"},
                uri = "/hello1",
                upstream = {
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    },
                    type = "roundrobin",
                    tls = {
                        client_cert = ssl_cert,
                        client_key = ssl_key
                    }
                }
            }

            update_route("2", data)

            local code = t.test("/hello1", ngx.HTTP_GET)
            assert(code == 200)

            assert(clear_route("1") == 200)
            assert(clear_route("2") == 200)
        }
    }
--- no_error_log
enable sample upstream



=== TEST 46: enable sample upstream
--- response_body
done



=== TEST 47: update r1 with service_name, disable sample upstream
--- yaml_config
discovery:                        # service discovery center
  dns:
    servers:
      - "127.0.0.1"
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local data = {
                methods = {"GET"},
                uri = "/hello",
                upstream = {
                    service_name = "sd.test.local",
                    discovery_type = "dns",
                    type = "roundrobin"
                }
            }

            update_route("1", data)

            local code = t("/hello", ngx.HTTP_GET)
            assert(code == 503)

            assert(clear_route("1") == 200)
        }
    }
--- no_error_log
enable sample upstream
--- error_log
discovery dns with host sd.test.local



=== TEST 48: enable sample upstream
--- response_body
done



=== TEST 49: add r2 with service_name, disable sample upstream
--- yaml_config
discovery:                        # service discovery center
  dns:
    servers:
      - "127.0.0.1"
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/mtls_client.crt")
            local ssl_key = t.read_file("t/certs/mtls_client.key")

            local data = {
                methods = {"GET"},
                uri = "/hello1",
                upstream = {
                    service_name = "sd.test.local",
                    discovery_type = "dns",
                    type = "roundrobin"
                }
            }

            update_route("2", data)

            local code = t.test("/hello1", ngx.HTTP_GET)
            assert(code == 503)

            assert(clear_route("1") == 200)
            assert(clear_route("2") == 200)
        }
    }
--- no_error_log
enable sample upstream
--- error_log
discovery dns with host sd.test.local
