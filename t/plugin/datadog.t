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
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    $block->set_value("stream_conf_enable", 1);

    if (!defined $block->extra_stream_config) {
        my $stream_config = <<_EOC_;
    server {
        listen 8125 udp;
        content_by_lua_block {
            require("lib.mock_dogstatsd").go()
        }
    }
_EOC_
        $block->set_value("extra_stream_config", $stream_config);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: sanity check metadata
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.datadog")
            local ok, err = plugin.check_schema({host = "127.0.0.1", port = 8125}, 2)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- setting the metadata
            local code, meta_body = t('/apisix/admin/plugin_metadata/datadog',
                 ngx.HTTP_PUT,
                 [[{
                        "host":"127.0.0.1",
                        "port": 8125
                }]],
                [[{
                    "node": {
                        "value": {
                            "namespace": "apisix",
                            "host": "127.0.0.1",
                            "constant_tags": [
                                "source:apisix"
                            ],
                            "port": 8125
                        },
                        "key": "/apisix/plugin_metadata/datadog"
                    },
                    "action": "set"
                }]])

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "datadog": {
                                "batch_max_size" : 1,
                                "max_retry_count": 1
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
                                "datadog": {
                                    "batch_max_size": 1,
                                    "max_retry_count": 1
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


            ngx.say(meta_body)
            ngx.say(body)
        }
    }
--- response_body
passed
passed



=== TEST 3: testing behaviour with mock suite
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, _, body = t("/opentracing", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.print(body)
        }
    }
--- wait: 0.5
--- response_body
opentracing
--- grep_error_log eval
qr/message received: apisix(.+?(?=, ))/
--- grep_error_log_out eval
qr/message received: apisix\.request\.counter:1\|c\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.request\.latency:[\d.]+\|h\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.upstream\.latency:[\d.]+\|h\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.apisix\.latency:[\d.]+\|h\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.ingress\.size:[\d]+\|ms\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.egress\.size:[\d]+\|ms\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
/



=== TEST 4: testing behaviour with multiple requests
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, _, body = t("/opentracing", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.print(body)

            -- request 2
            local code, _, body = t("/opentracing", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.print(body)
        }
    }
--- wait: 0.5
--- response_body
opentracing
opentracing
--- grep_error_log eval
qr/message received: apisix(.+?(?=, ))/
--- grep_error_log_out eval
qr/message received: apisix\.request\.counter:1\|c\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.request\.latency:[\d.]+\|h\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.upstream\.latency:[\d.]+\|h\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.apisix\.latency:[\d.]+\|h\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.ingress\.size:[\d]+\|ms\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.egress\.size:[\d]+\|ms\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.request\.counter:1\|c\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.request\.latency:[\d.]+\|h\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.upstream\.latency:[\d.]+\|h\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.apisix\.latency:[\d.]+\|h\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.ingress\.size:[\d]+\|ms\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.egress\.size:[\d]+\|ms\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
/



=== TEST 5: testing behaviour with different namespace
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- Change the metadata
            local code, meta_body = t('/apisix/admin/plugin_metadata/datadog',
                 ngx.HTTP_PUT,
                 [[{
                        "host":"127.0.0.1",
                        "port": 8125,
                        "namespace": "mycompany"
                }]],
                [[{
                    "node": {
                        "value": {
                            "namespace": "mycompany",
                            "host": "127.0.0.1",
                            "constant_tags": [
                                "source:apisix"
                            ],
                            "port": 8125
                        },
                        "key": "/apisix/plugin_metadata/datadog"
                    },
                    "action": "set"
                }]])

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.say(meta_body)

            local code, _, body = t("/opentracing", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.print(body)
        }
    }
--- wait: 0.5
--- response_body
passed
opentracing
--- grep_error_log eval
qr/message received: mycompany(.+?(?=, ))/
--- grep_error_log_out eval
qr/message received: mycompany\.request\.counter:1\|c\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: mycompany\.request\.latency:[\d.]+\|h\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: mycompany\.upstream\.latency:[\d.]+\|h\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: mycompany\.apisix\.latency:[\d.]+\|h\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: mycompany\.ingress\.size:[\d]+\|ms\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: mycompany\.egress\.size:[\d]+\|ms\|#source:apisix,route_id:1,balancer_ip:[\d.]+,response_status:200
/



=== TEST 6: testing behaviour with different namespace
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- Change the metadata
            local code, meta_body = t('/apisix/admin/plugin_metadata/datadog',
                 ngx.HTTP_PUT,
                 [[{
                        "host":"127.0.0.1",
                        "port": 8125,
                        "constant_tags": [
                                "source:apisix",
                                "new_tag:must"
                            ]
                }]],
                [[{
                    "node": {
                        "value": {
                            "namespace": "apisix",
                            "host": "127.0.0.1",
                            "constant_tags": [
                                "source:apisix",
                                "new_tag:must"
                            ],
                            "port": 8125
                        },
                        "key": "/apisix/plugin_metadata/datadog"
                    },
                    "action": "set"
                }]])

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.say(meta_body)

            local code, _, body = t("/opentracing", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end
            ngx.print(body)
        }
    }
--- wait: 0.5
--- response_body
passed
opentracing
--- grep_error_log eval
qr/message received: apisix(.+?(?=, ))/
--- grep_error_log_out eval
qr/message received: apisix\.request\.counter:1\|c\|#source:apisix,new_tag:must,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.request\.latency:[\d.]+\|h\|#source:apisix,new_tag:must,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.upstream\.latency:[\d.]+\|h\|#source:apisix,new_tag:must,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.apisix\.latency:[\d.]+\|h\|#source:apisix,new_tag:must,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.ingress\.size:[\d]+\|ms\|#source:apisix,new_tag:must,route_id:1,balancer_ip:[\d.]+,response_status:200
message received: apisix\.egress\.size:[\d]+\|ms\|#source:apisix,new_tag:must,route_id:1,balancer_ip:[\d.]+,response_status:200
/
