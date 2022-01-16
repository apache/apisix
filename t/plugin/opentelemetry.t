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
    - opentelemetry
plugin_attr:
    opentelemetry:
        batch_span_processor:
            max_export_batch_size: 1
            inactive_timeout: 0.5
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    my $extra_init_by_lua = <<_EOC_;
    -- mock exporter http client
    local client = require("opentelemetry.trace.exporter.http_client")
    client.do_request = function()
        ngx.log(ngx.INFO, "opentelemetry export span")
    end
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
                }]],
                [[{
                    "node": {
                        "value": {
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



=== TEST 2: trigger opentelemetry
--- request
GET /opentracing
--- response_body
opentracing
--- wait: 1
--- no_error_log
[error]
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
opentelemetry export span



=== TEST 3: use default always_off sampler
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "opentelemetry": {
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/opentracing"
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "opentelemetry": {
                                }
                            },
                            "upstream": {
                                "nodes": {
                                    "127.0.0.1:1980": 1
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



=== TEST 4: not trigger opentelemetry
--- request
GET /opentracing
--- response_body
opentracing
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
--- no_error_log
[error]



=== TEST 5: use trace_id_ratio sampler, default fraction = 0
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "opentelemetry": {
                            "sampler": {
                                "name": "trace_id_ratio"
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
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "opentelemetry": {
                                    "sampler": {
                                        "name": "trace_id_ratio"
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



=== TEST 6: not trigger opentelemetry
--- request
GET /opentracing
--- response_body
opentracing
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
--- no_error_log
[error]



=== TEST 7: use trace_id_ratio sampler, fraction = 1.0
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "opentelemetry": {
                            "sampler": {
                                "name": "trace_id_ratio",
                                "options": {
                                    "fraction": 1.0
                                }
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
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "opentelemetry": {
                                    "sampler": {
                                        "name": "trace_id_ratio",
                                        "options": {
                                            "fraction": 1.0
                                        }
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



=== TEST 8: trigger opentelemetry
--- request
GET /opentracing
--- response_body
opentracing
--- wait: 1
--- no_error_log
[error]
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
opentelemetry export span



=== TEST 9: use parent_base sampler, default root sampler = always_off
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "opentelemetry": {
                            "sampler": {
                                "name": "parent_base"
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
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "opentelemetry": {
                                    "sampler": {
                                        "name": "parent_base"
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



=== TEST 10: not trigger opentelemetry
--- request
GET /opentracing
--- response_body
opentracing
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
--- no_error_log
[error]



=== TEST 11: use parent_base sampler, root sampler = always_on
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "opentelemetry": {
                            "sampler": {
                                "name": "parent_base",
                                "options": {
                                    "root": {
                                        "name": "always_on"
                                    }
                                }
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
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "opentelemetry": {
                                    "sampler": {
                                        "name": "parent_base",
                                        "options": {
                                            "root": {
                                                "name": "always_on"
                                            }
                                        }
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



=== TEST 12: trigger opentelemetry
--- request
GET /opentracing
--- response_body
opentracing
--- wait: 1
--- no_error_log
[error]
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
opentelemetry export span



=== TEST 13: use parent_base sampler, root sampler = trace_id_ratio with default fraction = 0
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "opentelemetry": {
                            "sampler": {
                                "name": "parent_base",
                                "options": {
                                    "root": {
                                        "name": "trace_id_ratio"
                                    }
                                }
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
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "opentelemetry": {
                                    "sampler": {
                                        "name": "parent_base",
                                        "options": {
                                            "root": {
                                                "name": "trace_id_ratio"
                                            }
                                        }
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



=== TEST 14: not trigger opentelemetry
--- request
GET /opentracing
--- response_body
opentracing
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
--- no_error_log
[error]



=== TEST 15: trigger opentelemetry, trace_flag = 1
--- request
GET /opentracing
--- more_headers
traceparent: 00-00000000000000000000000000000001-0000000000000001-01
--- response_body
opentracing
--- wait: 1
--- no_error_log
[error]
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
opentelemetry export span



=== TEST 16: use parent_base sampler, root sampler = trace_id_ratio with fraction = 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "opentelemetry": {
                            "sampler": {
                                "name": "parent_base",
                                "options": {
                                    "root": {
                                        "name": "trace_id_ratio",
                                        "options": {
                                            "fraction": 1.0
                                        }
                                    }
                                }
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
                }]],
                [[{
                    "node": {
                        "value": {
                            "plugins": {
                                "opentelemetry": {
                                    "sampler": {
                                        "name": "parent_base",
                                        "options": {
                                            "root": {
                                                "name": "trace_id_ratio",
                                                "options": {
                                                    "fraction": 1.0
                                                }
                                            }
                                        }
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



=== TEST 17: trigger opentelemetry
--- request
GET /opentracing
--- response_body
opentracing
--- wait: 1
--- no_error_log
[error]
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
opentelemetry export span



=== TEST 18: not trigger opentelemetry, trace_flag = 0
--- request
GET /opentracing
--- more_headers
traceparent: 00-00000000000000000000000000000001-0000000000000001-00
--- response_body
opentracing
--- grep_error_log eval
qr/opentelemetry export span/
--- grep_error_log_out
--- no_error_log
[error]
