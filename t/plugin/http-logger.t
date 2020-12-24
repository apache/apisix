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

log_level('debug');
repeat_each(1);
no_long_string();
no_root_location();
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.http-logger")
            local ok, err = plugin.check_schema({uri = "http://127.0.0.1"})
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
[error]



=== TEST 2: full schema check
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.http-logger")
            local ok, err = plugin.check_schema({uri = "http://127.0.0.1",
                                                 auth_header = "Basic 123",
                                                 timeout = 3,
                                                 name = "http-logger",
                                                 max_retry_count = 2,
                                                 retry_delay = 2,
                                                 buffer_duration = 2,
                                                 inactive_timeout = 2,
                                                 batch_max_size = 500,
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
[error]



=== TEST 3: uri is missing
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.http-logger")
            local ok, err = plugin.check_schema({auth_header = "Basic 123",
                                                 timeout = 3,
                                                 name = "http-logger",
                                                 max_retry_count = 2,
                                                 retry_delay = 2,
                                                 buffer_duration = 2,
                                                 inactive_timeout = 2,
                                                 batch_max_size = 500,
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
property "uri" is required
done
--- no_error_log
[error]



=== TEST 4: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "http-logger": {
                                "uri": "http://127.0.0.1:1982/hello",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "http-logger": {
                                    "uri": "http://127.0.0.1:1982/hello",
                                    "batch_max_size": 1,
                                    "max_retry_count": 1,
                                    "retry_delay": 2,
                                    "buffer_duration": 2,
                                    "inactive_timeout": 2
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/opentracing"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
[error]



=== TEST 5: access local server
--- request
GET /opentracing
--- response_body
opentracing
--- error_log
Batch Processor[http logger] successfully processed the entries
--- wait: 0.5



=== TEST 6: set to the http external endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "http-logger": {
                                "uri": "http://127.0.0.1:8888/hello-world-http",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "http-logger": {
                                    "uri": "http://127.0.0.1:8888/hello-world-http",
                                    "batch_max_size": 1,
                                    "max_retry_count": 1,
                                    "retry_delay": 2,
                                    "buffer_duration": 2,
                                    "inactive_timeout": 2
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
[error]



=== TEST 7: access external endpoint
--- request
GET /hello
--- response_body
hello world
--- error_log
Batch Processor[http logger] successfully processed the entries
--- wait: 1.5



=== TEST 8: set wrong https endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "http-logger": {
                                "uri": "https://127.0.0.1:8888/hello-world-http",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello1"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "http-logger": {
                                    "uri": "https://127.0.0.1:8888/hello-world-http",
                                    "batch_max_size": 1,
                                    "max_retry_count": 1,
                                    "retry_delay": 2,
                                    "buffer_duration": 2,
                                    "inactive_timeout": 2
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello1"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
[error]



=== TEST 9: access wrong https endpoint
--- request
GET /hello1
--- response_body
hello1 world
--- error_log
failed to perform SSL with host[127.0.0.1] port[8888] handshake failed
--- wait: 1.5



=== TEST 10: set correct https endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "http-logger": {
                                "uri": "https://127.0.0.1:9999/hello-world-http",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello1"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "http-logger": {
                                    "uri": "https://127.0.0.1:9999/hello-world-http",
                                    "batch_max_size": 1,
                                    "max_retry_count": 1,
                                    "retry_delay": 2,
                                    "buffer_duration": 2,
                                    "inactive_timeout": 2
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello1"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
[error]



=== TEST 11: access correct https endpoint
--- request
GET /hello1
--- response_body
hello1 world
--- error_log
Batch Processor[http logger] successfully processed the entries
--- wait: 1.5



=== TEST 12: set batch max size to two
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "http-logger": {
                                "uri": "https://127.0.0.1:9999/hello-world-http",
                                "batch_max_size": 2,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello1"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "http-logger": {
                                    "uri": "https://127.0.0.1:9999/hello-world-http",
                                    "batch_max_size": 2,
                                    "max_retry_count": 1,
                                    "retry_delay": 2,
                                    "buffer_duration": 2,
                                    "inactive_timeout": 2
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello1"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
[error]



=== TEST 13: access route with batch max size twice
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello1"
            local res, err = httpc:request_uri(uri, { method = "GET"})
            res, err = httpc:request_uri(uri, { method = "GET"})
            ngx.status = res.status
            if res.status == 200 then
                ngx.say("hello1 world")
            end
        }
    }
--- request
GET /t
--- response_body
hello1 world
--- error_log
Batch Processor[http logger] batch max size has exceeded
transferring buffer entries to processing pipe line, buffercount[2]
Batch Processor[http logger] successfully processed the entries
--- wait: 1.5



=== TEST 14: set wrong port
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "http-logger": {
                                "uri": "http://127.0.0.1:9991/hello-world-http",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello1"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "http-logger": {
                                    "uri": "http://127.0.0.1:9991/hello-world-http",
                                    "batch_max_size": 1,
                                    "max_retry_count": 1,
                                    "retry_delay": 2,
                                    "buffer_duration": 2,
                                    "inactive_timeout": 2
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/hello1"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
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
[error]



=== TEST 15: access wrong port
--- request
GET /hello1
--- response_body
hello1 world
--- error_log
Batch Processor[http logger] failed to process entries: failed to connect to host[127.0.0.1] port[9991] connection refused
--- wait: 1.5



=== TEST 16: check uri
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.http-logger")
            local bad_uris = {
               "127.0.0.1",
               "127.0.0.1:1024",
            }
            for _, bad_uri in ipairs(bad_uris) do
                local ok, err = plugin.check_schema({uri = bad_uri})
                if ok then
                    ngx.say("mismatched ", bad)
                end
            end

            local good_uris = {
               "http://127.0.0.1:1024/x?aa=b",
               "http://127.0.0.1:1024?aa=b",
               "http://127.0.0.1:1024",
               "http://x.con",
               "https://x.con",
            }
            for _, good_uri in ipairs(good_uris) do
                local ok, err = plugin.check_schema({uri = good_uri})
                if not ok then
                    ngx.say("mismatched ", good)
                end
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 17: check plugin configuration updating
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body1 = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "http-logger": {
                                "uri": "http://127.0.0.1:1982/hello",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "http-logger": {
                                    "uri": "http://127.0.0.1:1982/hello",
                                    "batch_max_size": 1,
                                    "max_retry_count": 1,
                                    "retry_delay": 2,
                                    "buffer_duration": 2,
                                    "inactive_timeout": 2
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/opentracing"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            local code, _, body2 = t("/opentracing", "GET")
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            local code, body3 = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "http-logger": {
                                "uri": "http://127.0.0.1:1982/hello1",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "http-logger": {
                                    "uri": "http://127.0.0.1:1982/hello1",
                                    "batch_max_size": 1,
                                    "max_retry_count": 1,
                                    "retry_delay": 2,
                                    "buffer_duration": 2,
                                    "inactive_timeout": 2
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1982": 1
                                },
                                "type": "roundrobin"
                            },
                            "uri": "/opentracing"
                        },
                        "key": "/apisix/routes/1"
                    },
                    "action": "set"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            local code, _, body4 = t("/opentracing", "GET")
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.print(body1)
            ngx.print(body2)
            ngx.print(body3)
            ngx.print(body4)
        }
    }
--- request
GET /t
--- wait: 0.5
--- response_body
passedopentracing
passedopentracing
--- grep_error_log eval
qr/sending a batch logs to http:\/\/127.0.0.1:1982\/hello\d?/
--- grep_error_log_out
sending a batch logs to http://127.0.0.1:1982/hello
sending a batch logs to http://127.0.0.1:1982/hello1
