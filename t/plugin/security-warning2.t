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
no_long_string();
no_root_location();
add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});
run_tests();

__DATA__

=== TEST 1: opa with no TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.opa")
            local ok, err = plugin.check_schema({host = "http://127.0.0.1:8181", policy = "example/allow"})
            ngx.say(ok and "done" or err)
        }
    }
--- response_body
done
--- error_log
Using opa host with no TLS is a security risk



=== TEST 2: opa with TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.opa")
            local ok, err = plugin.check_schema({host = "https://127.0.0.1:8181", policy = "example/allow"})
            ngx.say(ok and "done" or err)
        }
    }
--- response_body
done
--- no_error_log
Using opa host with no TLS is a security risk



=== TEST 3: openid-connect with no TLS
--- config
    location /t {
        content_by_lua_block {

            local plugin = require("apisix.plugins.openid-connect")
            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "http://a.com",
                introspection_endpoint = "http://b.com",
                redirect_uri = "http://c.com",
                post_logout_redirect_uri = "http://d.com",
                proxy_opts = {
                    http_proxy = "http://e.com"
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
Using openid-connect discovery with no TLS is a security risk
Using openid-connect introspection_endpoint with no TLS is a security risk
Using openid-connect redirect_uri with no TLS is a security risk
Using openid-connect post_logout_redirect_uri with no TLS is a security risk
Using openid-connect proxy_opts.http_proxy with no TLS is a security risk



=== TEST 4: openid-connect with TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openid-connect")

            local ok, err = plugin.check_schema({
                client_id = "a",
                client_secret = "b",
                discovery = "https://a.com",
                introspection_endpoint = "https://b.com",
                redirect_uri = "https://c.com",
                post_logout_redirect_uri = "https://d.com",
                proxy_opts = {
                    http_proxy = "https://e.com"
                }
            })

            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- no_error_log
Using openid-connect discovery with no TLS is a security risk
Using openid-connect introspection_endpoint with no TLS is a security risk
Using openid-connect redirect_uri with no TLS is a security risk
Using openid-connect post_logout_redirect_uri with no TLS is a security risk
Using openid-connect proxy_opts.http_proxy with no TLS is a security risk



=== TEST 5: opentelemetry with no TLS
--- extra_yaml_config
plugins:
    - opentelemetry
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/opentelemetry',
                ngx.HTTP_PUT,
                [[{
                    "batch_span_processor": {
                        "max_export_batch_size": 1,
                        "inactive_timeout": 0.5
                    },
                    "trace_id_source": "x-request-id",
                    "collector": {
                        "address": "http://127.0.0.1:4318",
                        "request_timeout": 3,
                        "request_headers": {
                            "foo": "bar"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "opentelemetry": {
                            "sampler": {
                                "name": "always_on"
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
            end
            --- deleting this data so this doesn't effect when metadata schema is validated
            --- at init in next test.
            local code, body = t('/apisix/admin/plugin_metadata/opentelemetry',
                ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- error_log
Using opentelemetry collector.address with no TLS is a security risk



=== TEST 6: opentelemetery with TLS
--- extra_yaml_config
plugins:
    - opentelemetry
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/opentelemetry',
                ngx.HTTP_PUT,
                [[{
                    "batch_span_processor": {
                        "max_export_batch_size": 1,
                        "inactive_timeout": 0.5
                    },
                    "trace_id_source": "x-request-id",
                    "collector": {
                        "address": "https://127.0.0.1:4318",
                        "request_timeout": 3,
                        "request_headers": {
                            "foo": "bar"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "opentelemetry": {
                            "sampler": {
                                "name": "always_on"
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
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- no_error_log
Using opentelemetry collector.address with no TLS is a security risk



=== TEST 7: openwhisk with no TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openwhisk")
            local ok, err = plugin.check_schema({
                api_host = "http://127.0.0.1:3233",
                service_token = "test:test",
                namespace = "test",
                action = "test"
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
Using openwhisk api_host with no TLS is a security risk



=== TEST 8: openwhisk with TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.openwhisk")
            local ok, err = plugin.check_schema({api_host = "https://127.0.0.1:3233", service_token = "test:test", namespace = "test", action = "test"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- no_error_log
Using openwhisk api_host with no TLS is a security risk



=== TEST 9: rocketmq with no TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.rocketmq-logger")
            local ok, err = plugin.check_schema({
                 topic = "test",
                 key = "key1",
                 nameserver_list = {
                    "127.0.0.1:3"
                 },
                 use_tls = false
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
Keeping use_tls disabled in rocketmq-logger configuration is a security risk



=== TEST 10: rocketmq with TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.rocketmq-logger")
            local ok, err = plugin.check_schema({
                 topic = "test",
                 key = "key1",
                 nameserver_list = {
                    "127.0.0.1:3"
                 },
                 use_tls = true
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- response_body
done
--- no_error_log
Keeping use_tls disabled in rocketmq-logger configuration is a security risk



=== TEST 11: skywalking-logger with no TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.skywalking-logger")
            local ok, err = plugin.check_schema({endpoint_addr = "http://127.0.0.1"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
Using skywalking-logger endpoint_addr with no TLS is a security risk



=== TEST 12: skywalking-logger with TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.skywalking-logger")
            local ok, err = plugin.check_schema({endpoint_addr = "https://127.0.0.1"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- no_error_log
Using skywalking-logger endpoint_addr with no TLS is a security risk



=== TEST 13: skywalking with no TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.skywalking")
            local ok, err = plugin.check_schema({endpoint_addr = "http://127.0.0.1:12800"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- error_log
Using skywalking endpoint_addr with no TLS is a security risk



=== TEST 14: skywalking with TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.skywalking")
            local ok, err = plugin.check_schema({endpoint_addr = "https://127.0.0.1:12800"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
Using skywalking endpoint_addr with no TLS is a security risk



=== TEST 15: syslog with no TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.syslog")
            local ok, err = plugin.check_schema({
                 host = "127.0.0.1",
                 port = 5140,
                 tls = false
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- error_log
Keeping tls disabled in syslog configuration is a security risk



=== TEST 16: syslog with TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.syslog")
            local ok, err = plugin.check_schema({
                 host = "127.0.0.1",
                 port = 5140,
                 tls = true
            })
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
Keeping tls disabled in syslog configuration is a security risk



=== TEST 17: tcp-logger with no TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.tcp-logger")
            local ok, err = plugin.check_schema({host = "127.0.0.1", port = 3000, tls = false})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- error_log
Keeping tls disabled in tcp-logger configuration is a security risk



=== TEST 18: tcp-logger with TLS
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "tcp-logger": {
                                "host": "127.0.0.1",
                                "port": 3000,
                                "tls": true
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
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
Keeping tls disabled in tcp-logger configuration is a security risk



=== TEST 19: wolf-rbac with no TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.wolf-rbac")
            local conf = {
                server = "http://127.0.0.1:12180"
            }

            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("toolkit.json").encode(conf))
        }
    }
--- response_body_like eval
qr/\{"appid":"unset","header_prefix":"X-","server":"http:\/\/127\.0\.0\.1:12180"\}/
--- error_log
Using wolf-rbac server with no TLS is a security risk



=== TEST 20: wolf-rbac with TLS
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "wolf_rbac_unit_test",
                    "plugins": {
                        "wolf-rbac": {
                            "appid": "wolf-rbac-app",
                            "server": "https://127.0.0.1:1982"
                        }
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
--- no_error_log
Using wolf-rbac server with no TLS is a security risk



=== TEST 21: zipkin with no TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.zipkin")
            local ok, err = plugin.check_schema({endpoint = 'http://127.0.0.1', sample_ratio = 0.001})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- error_log
Using zipkin endpoint with no TLS is a security risk



=== TEST 22: zipkin with TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.zipkin")
            local ok, err = plugin.check_schema({endpoint = 'https://127.0.0.1', sample_ratio = 0.001})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
Using zipkin endpoint with no TLS is a security risk
