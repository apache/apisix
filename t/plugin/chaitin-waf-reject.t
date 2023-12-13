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

    my $stream_default_server = <<_EOC_;
    server {
        listen 8088;
        listen 8089;
        content_by_lua_block {
            require("lib.chaitin_waf_server").reject()
        }
    }
_EOC_

    $block->set_value("extra_stream_config", $stream_default_server);
    $block->set_value("stream_conf_enable", 1);

    # setup default conf.yaml
    my $extra_yaml_config = $block->extra_yaml_config // <<_EOC_;
apisix:
  stream_proxy:                 # TCP/UDP L4 proxy
   only: true                  # Enable L4 proxy only without L7 proxy.
   tcp:
     - addr: 9100              # Set the TCP proxy listening ports.
       tls: true
     - addr: "127.0.0.1:9101"
   udp:                        # Set the UDP proxy listening ports.
     - 9200
     - "127.0.0.1:9201"
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    if (!$block->request) {
        # use /do instead of /t because stream server will inject a default /t location
        $block->set_value("request", "GET /do");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests;

__DATA__

=== TEST 1: set route
--- config
    location /do {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugin_metadata/chaitin-waf',
                 ngx.HTTP_PUT,
                 [[{
                    "nodes": [
                        {
                            "host": "127.0.0.1",
                            "port": 8088
                        },
                        {
                            "host": "127.0.0.1",
                            "port": 8089
                        }
                    ]
                 }]]
                )

            if code >= 300 then
                ngx.status = code
                return ngx.print(body)
            end

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "chaitin-waf": {
                                "upstream": {
                                   "servers": ["httpbun.org"]
                               }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/*"
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



=== TEST 2: pass
--- request
GET /hello
--- error_code: 403
--- response_body
{"code": 403, "success":false, "message": "blocked by Chaitin SafeLine Web Application Firewall", "event_id": "b3c6ce574dc24f09a01f634a39dca83b"}
--- error_log
--- response_headers
X-APISIX-CHAITIN-WAF: yes
X-APISIX-CHAITIN-WAF-STATUS: 403
X-APISIX-CHAITIN-WAF-ACTION: reject
--- response_headers_like
X-APISIX-CHAITIN-WAF-TIME:
