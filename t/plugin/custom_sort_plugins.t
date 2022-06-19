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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

no_long_string();
no_root_location();
log_level("info");
run_tests;

__DATA__

=== TEST 1: custom priority and default priority on different routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-post-function": {
                            "_meta": {
                                "priority": 10000
                            },
                            "phase": "rewrite",
                            "functions" : ["return function(conf, ctx)
                                        ngx.say(\"serverless-post-function\");
                                        end"]
                        },
                        "serverless-pre-function": {
                            "_meta": {
                                "priority": -2000
                            },
                            "phase": "rewrite",
                            "functions": ["return function(conf, ctx)
                                        ngx.say(\"serverless-pre-function\");
                                        end"]
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
            end

            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-post-function": {
                            "phase": "rewrite",
                            "functions" : ["return function(conf, ctx)
                                        ngx.say(\"serverless-post-function\");
                                        end"]
                        },
                        "serverless-pre-function": {
                            "phase": "rewrite",
                            "functions": ["return function(conf, ctx)
                                        ngx.say(\"serverless-pre-function\");
                                        end"]
                        }
                    },
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
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: verify order
--- request
GET /hello
--- response_body
serverless-post-function
serverless-pre-function



=== TEST 3: routing without custom plugin order is not affected
--- request
GET /hello1
--- response_body
serverless-pre-function
serverless-post-function



=== TEST 4: custom priority and default priority on same route
# the priority of serverless-post-function is -2000, execute serverless-post-function first
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-post-function": {
                            "phase": "rewrite",
                            "functions" : ["return function(conf, ctx)
                                        ngx.say(\"serverless-post-function\");
                                        end"]
                        },
                        "serverless-pre-function": {
                            "_meta": {
                                "priority": -2001
                            },
                            "phase": "rewrite",
                            "functions": ["return function(conf, ctx)
                                        ngx.say(\"serverless-pre-function\");
                                        end"]
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
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 5: verify order
--- request
GET /hello
--- response_body
serverless-post-function
serverless-pre-function



=== TEST 6: merge plugins from consumer and route, execute the rewrite phase
# in the rewrite phase, the plugins on the route must be executed first,
# and then executed the rewrite phase of the plugins on the consumer,
# and the custom plugin order fails for this case.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-one"
                        },
                        "serverless-post-function": {
                            "_meta": {
                                "priority": 10000
                            },
                            "phase": "rewrite",
                            "functions" : ["return function(conf, ctx)
                                        ngx.say(\"serverless-post-function\");
                                        end"]
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {},
                        "serverless-pre-function": {
                            "_meta": {
                                "priority": -2000
                            },
                            "phase": "rewrite",
                            "functions": ["return function(conf, ctx)
                                        ngx.say(\"serverless-pre-function\");
                                        end"]
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
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 7: verify order(more requests)
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local httpc = http.new()
            local headers = {}
            headers["apikey"] = "auth-one"
            local res, err = httpc:request_uri(uri, {method = "GET", headers = headers})
            if not res then
                ngx.say(err)
                return
            end
            ngx.print(res.body)

            local res, err = httpc:request_uri(uri, {method = "GET", headers = headers})
            if not res then
                ngx.say(err)
                return
            end
            ngx.print(res.body)
        }
    }
--- response_body
serverless-pre-function
serverless-post-function
serverless-pre-function
serverless-post-function



=== TEST 8: merge plugins form custom and route, execute the access phase
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-one"
                        },
                        "serverless-post-function": {
                            "_meta": {
                                "priority": 10000
                            },
                            "phase": "access",
                            "functions" : ["return function(conf, ctx)
                                        ngx.say(\"serverless-post-function\");
                                        end"]
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {},
                        "serverless-pre-function": {
                            "_meta": {
                                "priority": -2000
                            },
                            "phase": "access",
                            "functions": ["return function(conf, ctx)
                                        ngx.say(\"serverless-pre-function\");
                                        end"]
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
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 9: verify order
--- request
GET /hello
--- more_headers
apikey: auth-one
--- response_body
serverless-post-function
serverless-pre-function



=== TEST 10: merge plugins form service and route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-post-function": {
                            "_meta": {
                                "priority": 10000
                            },
                            "phase": "rewrite",
                            "functions" : ["return function(conf, ctx)
                                        ngx.say(\"serverless-post-function\");
                                        end"]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "_meta": {
                                "priority": -2000
                            },
                            "phase": "rewrite",
                            "functions": ["return function(conf, ctx)
                                        ngx.say(\"serverless-pre-function\");
                                        end"]
                        }
                    },
                    "service_id": "1",
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



=== TEST 11: verify order
--- request
GET /hello
--- response_body
serverless-post-function
serverless-pre-function



=== TEST 12: custom plugins sort is not affected by plugins reload
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri)
            if not res then
                ngx.say(err)
                return
            end
            ngx.print(res.body)

            local t = require("lib.test_admin").test
            local code, _, org_body = t('/apisix/admin/plugins/reload',
                                        ngx.HTTP_PUT)

            ngx.say(org_body)

            ngx.sleep(0.2)

            local res, err = httpc:request_uri(uri)
            if not res then
                ngx.say(err)
                return
            end
            ngx.print(res.body)
        }
    }
--- response_body
serverless-post-function
serverless-pre-function
done
serverless-post-function
serverless-pre-function



=== TEST 13: merge plugins form plugin_configs and route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, err = t('/apisix/admin/plugin_configs/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-post-function": {
                            "_meta": {
                                "priority": 10000
                            },
                            "phase": "rewrite",
                            "functions" : ["return function(conf, ctx)
                                        ngx.say(\"serverless-post-function\");
                                        end"]
                        }
                    }
                }]]
            )
            if code > 300 then
                ngx.status = code
                ngx.say(body)
            end

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-pre-function": {
                            "_meta": {
                                "priority": -2000
                            },
                            "phase": "rewrite",
                            "functions": ["return function(conf, ctx)
                                        ngx.say(\"serverless-pre-function\");
                                        end"]
                        }
                    },
                    "plugin_config_id": 1,
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
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 14: verify order
--- request
GET /hello
--- response_body
serverless-post-function
serverless-pre-function



=== TEST 15: custom plugins sort on global_rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "serverless-post-function": {
                            "_meta": {
                                "priority": 10000
                            },
                            "phase": "rewrite",
                            "functions" : ["return function(conf, ctx)
                                        ngx.say(\"serverless-post-function on global rule\");
                                        end"]
                        },
                        "serverless-pre-function": {
                            "_meta": {
                                "priority": -2000
                            },
                            "phase": "rewrite",
                            "functions": ["return function(conf, ctx)
                                        ngx.say(\"serverless-pre-function on global rule\");
                                        end"]
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 16: verify order
--- request
GET /hello
--- response_body
serverless-post-function on global rule
serverless-pre-function on global rule
serverless-post-function
serverless-pre-function



=== TEST 17: delete global rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_DELETE
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
            end
            ngx.say(body)
        }
    }
--- response_body
passed
