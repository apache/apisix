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
    $block->set_value("extra_yaml_config", "stream_plugins:\n    - prometheus\n");
    $block->set_value("stream_conf_enable", 1);
    $block->set_value("extra_stream_config", <<'_EOC_');
server {
    listen 1993;
    content_by_lua_block {
        local prom = require("apisix.plugins.prometheus.exporter").get_prometheus()
        ngx.say(prom.remove_expired_keys_interval, ":", prom.auto_flush_expired, ":", prom.prefix)
    }
}
_EOC_
    $block->set_value("config", <<'_EOC_');
    location /t {
        content_by_lua_block {
            local prom = require("apisix.plugins.prometheus.exporter").get_prometheus()
            ngx.say("http: ", prom.remove_expired_keys_interval, ":",
                    prom.auto_flush_expired, ":", prom.prefix)
            local sock = ngx.socket.tcp()
            assert(sock:connect("127.0.0.1", 1993))
            ngx.say("stream: ", assert(sock:receive("*l")))
            sock:close()
        }
    }
_EOC_
    $block->set_value("request", "GET /t");
});

run_tests;

__DATA__

=== TEST 1: default cleanup interval
--- response_body
http: 3600:true:apisix_
stream: 3600:true:apisix_
--- no_error_log
[error]



=== TEST 2: custom cleanup interval and metric prefix
--- yaml_config
plugin_attr:
    prometheus:
        remove_expired_keys_interval: 30
        metric_prefix: custom_
--- response_body
http: 30:true:custom_
stream: 30:true:custom_
--- no_error_log
[error]



=== TEST 3: cleanup interval is capped
--- yaml_config
plugin_attr:
    prometheus:
        remove_expired_keys_interval: 7200
        metric_prefix: apisix_
--- response_body
http: 3600:true:apisix_
stream: 3600:true:apisix_
--- no_error_log
[error]



=== TEST 4: zero disables cleanup
--- yaml_config
plugin_attr:
    prometheus:
        remove_expired_keys_interval: 0
        metric_prefix: apisix_
--- response_body
http: 0:true:apisix_
stream: 0:true:apisix_
--- no_error_log
[error]



=== TEST 5: negative interval disables cleanup
--- yaml_config
plugin_attr:
    prometheus:
        remove_expired_keys_interval: -1
        metric_prefix: apisix_
--- response_body
http: -1:true:apisix_
stream: -1:true:apisix_
--- no_error_log
[error]
