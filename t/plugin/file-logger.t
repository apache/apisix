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

no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (! $block->request) {
        $block->set_value("request", "GET /t");
    }
});


run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local configs = {
                -- full configuration
                {
                    path = "file.log"
                },
                -- property "path" is not set in either the plugin conf or the metadata
                {
                    path = nil
                }
            }

            local plugin = require("apisix.plugins.file-logger")

            for i = 1, #configs do
                ok, err = plugin.check_schema(configs[i])
                if err then
                    ngx.say(err)
                else
                    ngx.say("done")
                end
            end
        }
    }
--- response_body_like
done
property "path" is not set in either the plugin conf or the metadata



=== TEST 2: add plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/file-logger',
                ngx.HTTP_PUT,
                [[{
                    "log_format": {
                        "host": "$host",
                        "client_ip": "$remote_addr"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 3: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file.log"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: verify plugin
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello", ngx.HTTP_GET)
            local fd, err = io.open("file.log", 'r')
            local msg

            if not fd then
                core.log.error("failed to open file: file.log, error info: ", err)
                return
            end

            msg = fd:read()

            local new_msg = core.json.decode(msg)
            if new_msg.client_ip == '127.0.0.1' and new_msg.route_id == '1'
                and new_msg.host == '127.0.0.1'
            then
                msg = "write file log success"
                ngx.status = code
                ngx.say(msg)
            end

            --- a new request is logged
            t("/hello", ngx.HTTP_GET)
            msg = fd:read("*l")
            local new_msg = core.json.decode(msg)
            if new_msg.client_ip == '127.0.0.1' and new_msg.route_id == '1'
                and new_msg.host == '127.0.0.1'
            then
                msg = "write file log success"
                ngx.say(msg)
            end
        }
    }
--- response_body
write file log success
write file log success



=== TEST 5: failed to open the path
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "/log/file.log"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
            end

            local code, messages = t("/hello", GET)
            core.log.warn("messages: ", messages)
            if code >= 300 then
                ngx.status = code
            end
        }
    }
--- error_log
failed to open file: /log/file.log, error info: /log/file.log: No such file or directory



=== TEST 6: log format in plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- ensure the format is not set
            t('/apisix/admin/plugin_metadata/file-logger',
                ngx.HTTP_DELETE
            )
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file.log",
                                "log_format": {
                                    "host": "$host",
                                    "client_ip": "$remote_addr"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 7: verify plugin
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello", ngx.HTTP_GET)
            local fd, err = io.open("file.log", 'r')
            local msg

            if not fd then
                core.log.error("failed to open file: file.log, error info: ", err)
                return
            end

            msg = fd:read()

            local new_msg = core.json.decode(msg)
            if new_msg.client_ip == '127.0.0.1' and new_msg.route_id == '1'
                and new_msg.host == '127.0.0.1'
            then
                msg = "write file log success"
                ngx.status = code
                ngx.say(msg)
            end
        }
    }
--- response_body
write file log success



=== TEST 8: add plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/file-logger',
                ngx.HTTP_PUT,
                [[{
                    "log_format": {
                        "host": "$host"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 9: ensure config in plugin is prior to the one in plugin metadata
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello", ngx.HTTP_GET)
            local fd, err = io.open("file.log", 'r')
            local msg

            if not fd then
                core.log.error("failed to open file: file.log, error info: ", err)
                return
            end

            msg = fd:read()

            local new_msg = core.json.decode(msg)
            if new_msg.client_ip == '127.0.0.1' and new_msg.route_id == '1'
                and new_msg.host == '127.0.0.1'
            then
                msg = "write file log success"
                ngx.status = code
                ngx.say(msg)
            end
        }
    }
--- response_body
write file log success



=== TEST 10: nested log format in plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file-logger-nested.log",
                                "log_format": {
                                    "host": "$host",
                                    "client_ip": "$remote_addr",
                                    "request": {
                                        "method": "$request_method",
                                        "uri": "$request_uri",
                                        "headers": {
                                            "user_agent": "$http_user_agent"
                                        }
                                    },
                                    "response": {
                                        "status": "$status"
                                    }
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: verify nested log format structure
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello", ngx.HTTP_GET)
            local fd, err = io.open("file-logger-nested.log", 'r')
            local msg

            if not fd then
                core.log.error("failed to open file: file-logger-nested.log, error info: ", err)
                return
            end

            msg = fd:read()
            fd:close()

            local new_msg = core.json.decode(msg)
            if new_msg.host == '127.0.0.1' and
               new_msg.client_ip == '127.0.0.1' and
               type(new_msg.request) == "table" and
               new_msg.request.method == 'GET' and
               new_msg.request.uri == '/hello' and
               type(new_msg.request.headers) == "table" and
               new_msg.request.headers.user_agent and
               type(new_msg.response) == "table" and
               new_msg.response.status == 200 and
               new_msg.route_id == '1'
            then
                msg = "nested log format success"
                ngx.status = code
                ngx.say(msg)
            else
                ngx.say("nested log format failed")
            end
        }
    }
--- response_body
nested log format success



=== TEST 12: deep nested log_format is truncated and warns
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            -- configure deep nested log_format
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file-logger-depth.log",
                                "log_format": {
                                    "a": {"b": {"c": {"d": {"e": {"f": {"g": "$host"}}}}}}
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
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

            -- trigger logging
            local code2 = t("/hello", ngx.HTTP_GET)

            -- read and verify depth truncation
            local fd, err = io.open("file-logger-depth.log", 'r')
            if not fd then
                core.log.error("failed to open file: file-logger-depth.log, error info: ", err)
                return
            end

            local msg = fd:read()
            fd:close()

            local new_msg = core.json.decode(msg)
            local ok = type(new_msg.a) == "table" and
                       type(new_msg.a.b) == "table" and
                       type(new_msg.a.b.c) == "table" and
                       type(new_msg.a.b.c.d) == "table" and
                       type(new_msg.a.b.c.d.e) == "table" and
                       new_msg.a.b.c.d.e.f == nil

            if ok then
                ngx.status = code2
                ngx.say("depth limit enforced")
            else
                ngx.say("depth limit not enforced")
            end
        }
    }
--- response_body
depth limit enforced
--- error_log
log_format nesting exceeds max depth 5, truncating



=== TEST 13: configure metadata path
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/file-logger',
                ngx.HTTP_PUT,
                [[{
                    "path": "file-from-metadata.log"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 14: use metadata path when plugin config does not set it
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "file-logger": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
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

            local res_code = t("/hello", ngx.HTTP_GET)
            local fd, err = io.open("file-from-metadata.log", 'r')
            if not fd then
                core.log.error("failed to open file: file-from-metadata.log, error info: ", err)
                return
            end

            local msg = fd:read()
            fd:close()

            local new_msg = core.json.decode(msg)
            if new_msg and new_msg.route_id == '1' then
                ngx.status = res_code
                ngx.say("write file log success")
            end
        }
    }
--- response_body
write file log success



=== TEST 15: log_format_extra enriches the default log without replacing it
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- additive log format via plugin metadata: keep the rich default and
            -- add the pre-DNS upstream host on top
            local code, body = t('/apisix/admin/plugin_metadata/file-logger',
                ngx.HTTP_PUT,
                [[{
                    "path": "file-logger-extra.log",
                    "log_format_extra": {
                        "upstream_host": "$upstream_unresolved_host"
                    }
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
                        "plugins": {
                            "file-logger": {}
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 16: default fields stay and the extra field is added
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello", ngx.HTTP_GET)
            local fd, err = io.open("file-logger-extra.log", 'r')
            if not fd then
                core.log.error("failed to open file: file-logger-extra.log, error info: ", err)
                return
            end
            local msg = fd:read()
            fd:close()

            local new_msg = core.json.decode(msg)
            -- the extra field is present
            if new_msg.upstream_host == '127.0.0.1' and
               -- and the rich default fields are still there
               type(new_msg.request) == "table" and
               new_msg.request.method == 'GET' and
               type(new_msg.response) == "table" and
               new_msg.response.status == 200 and
               type(new_msg.server) == "table" and
               new_msg.server.version and
               new_msg.route_id == '1'
            then
                ngx.status = code
                ngx.say("enrich log format success")
            else
                ngx.say("enrich log format failed: " .. msg)
            end
        }
    }
--- response_body
enrich log format success



=== TEST 17: log_format_extra logs the pre-DNS host for a domain upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/file-logger',
                ngx.HTTP_PUT,
                [[{
                    "path": "file-logger-domain.log",
                    "log_format_extra": {
                        "upstream_host": "$upstream_unresolved_host"
                    }
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
                        "plugins": {
                            "file-logger": {}
                        },
                        "upstream": {
                            "nodes": {
                                "localhost:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 18: extra field keeps the domain while the default upstream is resolved
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello", ngx.HTTP_GET)
            local fd, err = io.open("file-logger-domain.log", 'r')
            if not fd then
                core.log.error("failed to open file: file-logger-domain.log, error info: ", err)
                return
            end
            local msg = fd:read()
            fd:close()

            local new_msg = core.json.decode(msg)
            -- the extra field carries the configured hostname, before DNS
            if new_msg.upstream_host == 'localhost' and
               -- while the default upstream field is the resolved ip:port
               new_msg.upstream == '127.0.0.1:1982' and
               -- and the rich default fields are still there
               type(new_msg.request) == "table" and
               new_msg.request.method == 'GET' and
               type(new_msg.response) == "table" and
               new_msg.response.status == 200 and
               type(new_msg.server) == "table" and
               new_msg.server.version and
               new_msg.route_id == '1'
            then
                ngx.status = code
                ngx.say("enrich log format success")
            else
                ngx.say("enrich log format failed: " .. msg)
            end
        }
    }
--- response_body
enrich log format success



=== TEST 19: log_format wins and log_format_extra is ignored when both are set
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file-logger-precedence.log",
                                "log_format": {
                                    "msg": "precedence test"
                                },
                                "log_format_extra": {
                                    "upstream_host": "$upstream_unresolved_host"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 20: extra field absent and the default entry is replaced by log_format
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello", ngx.HTTP_GET)
            local fd, err = io.open("file-logger-precedence.log", 'r')
            if not fd then
                core.log.error("failed to open file: file-logger-precedence.log, error info: ", err)
                return
            end
            local msg = fd:read()
            fd:close()

            local new_msg = core.json.decode(msg)
            -- log_format replaced the default entry, extra was ignored
            if new_msg.msg == 'precedence test' and
               new_msg.upstream_host == nil and
               new_msg.request == nil and
               new_msg.response == nil
            then
                ngx.status = code
                ngx.say("log_format precedence success")
            else
                ngx.say("log_format precedence failed: " .. msg)
            end
        }
    }
--- response_body
log_format precedence success



=== TEST 21: route-level log_format_extra overrides the metadata one
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- metadata carries one extra field
            local code, body = t('/apisix/admin/plugin_metadata/file-logger',
                ngx.HTTP_PUT,
                [[{
                    "log_format_extra": {
                        "meta_only": "from metadata"
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- the route sets its own, which must fully replace the metadata one
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file-logger-override.log",
                                "log_format_extra": {
                                    "route_field": "from route"
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 22: only the route extra field is present, metadata one is dropped
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello", ngx.HTTP_GET)
            local fd, err = io.open("file-logger-override.log", 'r')
            if not fd then
                core.log.error("failed to open file: file-logger-override.log, error info: ", err)
                return
            end
            local msg = fd:read()
            fd:close()

            local new_msg = core.json.decode(msg)
            -- route extra wins, metadata extra is gone, default fields stay
            if new_msg.route_field == 'from route' and
               new_msg.meta_only == nil and
               type(new_msg.request) == "table" and
               new_msg.request.method == 'GET' and
               new_msg.route_id == '1'
            then
                ngx.status = code
                ngx.say("route extra precedence success")
            else
                ngx.say("route extra precedence failed: " .. msg)
            end
        }
    }
--- response_body
route extra precedence success



=== TEST 23: log_format_extra logs the pre-DNS host for a multi-node domain upstream
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/file-logger',
                ngx.HTTP_PUT,
                [[{
                    "log_format_extra": {
                        "upstream_host": "$upstream_unresolved_host"
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- two domain nodes exercise the server_picker path in balancer.lua
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file-logger-multinode.log"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "localhost:1980": 1,
                                "localhost:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 24: the picked node's pre-DNS host is logged regardless of which one is chosen
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code = t("/hello", ngx.HTTP_GET)
            local fd, err = io.open("file-logger-multinode.log", 'r')
            if not fd then
                core.log.error("failed to open file: file-logger-multinode.log, error info: ", err)
                return
            end
            local msg = fd:read()
            fd:close()

            local new_msg = core.json.decode(msg)
            -- both nodes share the host "localhost", so whichever is picked logs it
            if new_msg.upstream_host == 'localhost' and
               type(new_msg.request) == "table" and
               new_msg.request.method == 'GET' and
               new_msg.route_id == '1'
            then
                ngx.status = code
                ngx.say("enrich log format success")
            else
                ngx.say("enrich log format failed: " .. msg)
            end
        }
    }
--- response_body
enrich log format success



=== TEST 25: multi-node upstream mixing a domain node and a raw-IP node
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/file-logger',
                ngx.HTTP_PUT,
                [[{
                    "log_format_extra": {
                        "upstream_host": "$upstream_unresolved_host"
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- distinct hosts prove addr_to_domain maps each picked node to its own host
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "file-logger": {
                                "path": "file-logger-mixed.log"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "localhost:1980": 1,
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 26: each node logs its own pre-DNS host, domain resolved and raw IP untouched
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            -- round-robin over two equal nodes visits both within the cycle
            for _ = 1, 4 do
                t("/hello", ngx.HTTP_GET)
            end
            local fd, err = io.open("file-logger-mixed.log", 'r')
            if not fd then
                core.log.error("failed to open file: file-logger-mixed.log, error info: ", err)
                return
            end

            -- collect the pre-DNS host logged for each resolved upstream
            local host_by_upstream = {}
            for line in fd:lines() do
                local m = core.json.decode(line)
                host_by_upstream[m.upstream] = m.upstream_host
            end
            fd:close()

            -- domain node logs its hostname, raw-IP node falls back to the ip
            if host_by_upstream['127.0.0.1:1980'] == 'localhost' and
               host_by_upstream['127.0.0.1:1982'] == '127.0.0.1'
            then
                ngx.say("enrich log format success")
            else
                ngx.say("enrich log format failed: "
                        .. core.json.encode(host_by_upstream))
            end
        }
    }
--- response_body
enrich log format success
