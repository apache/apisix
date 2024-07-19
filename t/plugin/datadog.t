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
            require("lib.mock_layer4").dogstatsd()
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
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.datadog")
            local ok, err = plugin.check_schema({host = "127.0.0.1", port = 8125}, core.schema.TYPE_METADATA)
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
                }]]
                )

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
                                "max_retry_count": 0
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "name": "datadog",
                        "uri": "/opentracing"
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
qr/message received: apisix\.request\.counter:1\|c\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.request\.latency:[\d.]+\|h\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.upstream\.latency:[\d.]+\|h\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.apisix\.latency:[\d.]+\|h\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.ingress\.size:[\d]+\|ms\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.egress\.size:[\d]+\|ms\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
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
qr/message received: apisix\.request\.counter:1\|c\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.request\.latency:[\d.]+\|h\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.upstream\.latency:[\d.]+\|h\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.apisix\.latency:[\d.]+\|h\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.ingress\.size:[\d]+\|ms\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.egress\.size:[\d]+\|ms\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.request\.counter:1\|c\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.request\.latency:[\d.]+\|h\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.upstream\.latency:[\d.]+\|h\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.apisix\.latency:[\d.]+\|h\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.ingress\.size:[\d]+\|ms\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.egress\.size:[\d]+\|ms\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
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
qr/message received: mycompany\.request\.counter:1\|c\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: mycompany\.request\.latency:[\d.]+\|h\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: mycompany\.upstream\.latency:[\d.]+\|h\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: mycompany\.apisix\.latency:[\d.]+\|h\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: mycompany\.ingress\.size:[\d]+\|ms\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: mycompany\.egress\.size:[\d]+\|ms\|#source:apisix,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
/



=== TEST 6: testing behaviour with different constant tags
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
qr/message received: apisix\.request\.counter:1\|c\|#source:apisix,new_tag:must,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.request\.latency:[\d.]+\|h\|#source:apisix,new_tag:must,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.upstream\.latency:[\d.]+\|h\|#source:apisix,new_tag:must,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.apisix\.latency:[\d.]+\|h\|#source:apisix,new_tag:must,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.ingress\.size:[\d]+\|ms\|#source:apisix,new_tag:must,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.egress\.size:[\d]+\|ms\|#source:apisix,new_tag:must,route_name:datadog,balancer_ip:[\d.]+,response_status:200,scheme:http
/



=== TEST 7: testing behaviour when route_name is missing - must fallback to route_id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "datadog": {
                                "batch_max_size" : 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)

            -- making a request to the route
            local code, _, body = t("/opentracing", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.print(body)
        }
    }
--- response_body
passed
opentracing
--- wait: 0.5
--- grep_error_log eval
qr/message received: apisix(.+?(?=, ))/
--- grep_error_log_out eval
qr/message received: apisix\.request\.counter:1\|c\|#source:apisix,new_tag:must,route_name:1,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.request\.latency:[\d.]+\|h\|#source:apisix,new_tag:must,route_name:1,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.upstream\.latency:[\d.]+\|h\|#source:apisix,new_tag:must,route_name:1,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.apisix\.latency:[\d.]+\|h\|#source:apisix,new_tag:must,route_name:1,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.ingress\.size:[\d]+\|ms\|#source:apisix,new_tag:must,route_name:1,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.egress\.size:[\d]+\|ms\|#source:apisix,new_tag:must,route_name:1,balancer_ip:[\d.]+,response_status:200,scheme:http
/



=== TEST 8: testing behaviour with service id
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                        "name": "service-1",
                        "plugins": {
                            "datadog": {
                                "batch_max_size" : 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)

            -- create a route with service level abstraction
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                       "name": "route-1",
                       "uri": "/opentracing",
                       "service_id": "1"

                 }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)

            -- making a request to the route
            local code, _, body = t("/opentracing", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.print(body)
        }
    }
--- response_body
passed
passed
opentracing
--- wait: 0.5
--- grep_error_log eval
qr/message received: apisix(.+?(?=, ))/
--- grep_error_log_out eval
qr/message received: apisix\.request\.counter:1\|c\|#source:apisix,new_tag:must,route_name:route-1,service_name:service-1,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.request\.latency:[\d.]+\|h\|#source:apisix,new_tag:must,route_name:route-1,service_name:service-1,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.upstream\.latency:[\d.]+\|h\|#source:apisix,new_tag:must,route_name:route-1,service_name:service-1,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.apisix\.latency:[\d.]+\|h\|#source:apisix,new_tag:must,route_name:route-1,service_name:service-1,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.ingress\.size:[\d]+\|ms\|#source:apisix,new_tag:must,route_name:route-1,service_name:service-1,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.egress\.size:[\d]+\|ms\|#source:apisix,new_tag:must,route_name:route-1,service_name:service-1,balancer_ip:[\d.]+,response_status:200,scheme:http
/



=== TEST 9: testing behaviour with prefer_name is false and service name is nil
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "datadog": {
                                "batch_max_size" : 1,
                                "prefer_name": false
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)

            -- making a request to the route
            local code, _, body = t("/opentracing", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.print(body)
        }
    }
--- response_body
passed
opentracing
--- wait: 0.5
--- grep_error_log eval
qr/message received: apisix(.+?(?=, ))/
--- grep_error_log_out eval
qr/message received: apisix\.request\.counter:1\|c\|#source:apisix,new_tag:must,route_name:1,service_name:1,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.request\.latency:[\d.]+\|h\|#source:apisix,new_tag:must,route_name:1,service_name:1,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.upstream\.latency:[\d.]+\|h\|#source:apisix,new_tag:must,route_name:1,service_name:1,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.apisix\.latency:[\d.]+\|h\|#source:apisix,new_tag:must,route_name:1,service_name:1,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.ingress\.size:[\d]+\|ms\|#source:apisix,new_tag:must,route_name:1,service_name:1,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.egress\.size:[\d]+\|ms\|#source:apisix,new_tag:must,route_name:1,service_name:1,balancer_ip:[\d.]+,response_status:200,scheme:http
/



=== TEST 10: testing behaviour with consumer
--- apisix_yaml
consumers:
  - username: user0
    plugins:
      key-auth:
        key: user0
routes:
  - uri: /opentracing
    name: datadog
    upstream:
      nodes:
        "127.0.0.1:1982": 1
    plugins:
      datadog:
        batch_max_size: 1
        max_retry_count: 0
      key-auth: {}
#END
--- request
GET /opentracing?apikey=user0
--- response_body
opentracing
--- wait: 0.5
--- grep_error_log eval
qr/message received: apisix(.+?(?=, ))/
--- grep_error_log_out eval
qr/message received: apisix\.request\.counter:1\|c\|#source:apisix,route_name:datadog,consumer:user0,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.request\.latency:[\d.]+\|h\|#source:apisix,route_name:datadog,consumer:user0,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.upstream\.latency:[\d.]+\|h\|#source:apisix,route_name:datadog,consumer:user0,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.apisix\.latency:[\d.]+\|h\|#source:apisix,route_name:datadog,consumer:user0,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.ingress\.size:[\d]+\|ms\|#source:apisix,route_name:datadog,consumer:user0,balancer_ip:[\d.]+,response_status:200,scheme:http
message received: apisix\.egress\.size:[\d]+\|ms\|#source:apisix,route_name:datadog,consumer:user0,balancer_ip:[\d.]+,response_status:200,scheme:http
/
