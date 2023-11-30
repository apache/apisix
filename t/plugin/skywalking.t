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

    my $extra_yaml_config = <<_EOC_;
plugins:
    - example-plugin
    - key-auth
    - skywalking
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    my $extra_init_by_lua = <<_EOC_;
    -- reduce default report interval
    local client = require("skywalking.client")
    client.backendTimerDelay = 0.5

    local sw_tracer = require("skywalking.tracer")
    local inject = function(mod, name)
        local old_f = mod[name]
        mod[name] = function (...)
            ngx.log(ngx.WARN, "skywalking run ", name)
            return old_f(...)
        end
    end

    inject(sw_tracer, "start")
    inject(sw_tracer, "finish")
    inject(sw_tracer, "prepareForReport")
_EOC_

    $block->set_value("extra_init_by_lua", $extra_init_by_lua);

    $block;
});

repeat_each(1);
no_long_string();
no_root_location();
log_level("debug");

run_tests;

__DATA__

=== TEST 1: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "skywalking": {
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/opentracing"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: trigger skywalking
--- request
GET /opentracing
--- response_body
opentracing
--- grep_error_log eval
qr/skywalking run \w+/
--- grep_error_log_out
skywalking run start
skywalking run finish
skywalking run prepareForReport
--- wait: 1



=== TEST 3: change sample ratio
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "skywalking": {
                            "sample_ratio": 0.00001
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/opentracing"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 4: not trigger skywalking
--- request
GET /opentracing
--- response_body
opentracing
--- grep_error_log eval
qr/skywalking run \w+/
--- grep_error_log_out



=== TEST 5: disabled
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/opentracing"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 6: not trigger skywalking
--- request
GET /opentracing
--- response_body
opentracing
--- no_error_log
rewrite phase of skywalking plugin



=== TEST 7: enable skywalking(sample_ratio=1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "skywalking": {
                                "sample_ratio": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 8: test segments report
--- request
GET /opentracing
--- response_body
opentracing
--- grep_error_log eval
qr/skywalking run \w+/
--- grep_error_log_out
skywalking run start
skywalking run finish
skywalking run prepareForReport
--- wait: 1



=== TEST 9: enable at both global and route levels
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "skywalking": {
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/opentracing"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return
            end

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "skywalking": {
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 10: run once
--- request
GET /opentracing
--- response_body
opentracing
--- grep_error_log eval
qr/skywalking run \w+/
--- grep_error_log_out
skywalking run start
skywalking run finish
skywalking run prepareForReport



=== TEST 11: enable at global but disable at route levels
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "skywalking": {
                            "_meta": {
                                "disable": true
                            }
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/opentracing"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return
            end

            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "skywalking": {
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 12: run once
--- request
GET /opentracing
--- response_body
opentracing
--- grep_error_log eval
qr/skywalking run \w+/
--- grep_error_log_out
skywalking run start
skywalking run finish
skywalking run prepareForReport



=== TEST 13: delete global rule
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1', ngx.HTTP_DELETE)

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 14: trace request rejected by auth
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
                        }
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
                        "key-auth": {},
                        "example-plugin": {"i": 1},
                        "skywalking": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/opentracing"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 15: hit
--- request
GET /opentracing
--- error_code: 401
--- grep_error_log eval
qr/(skywalking run \w+|plugin body_filter phase)/
--- grep_error_log_out
skywalking run start
plugin body_filter phase
plugin body_filter phase
skywalking run finish
skywalking run prepareForReport
