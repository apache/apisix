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
# The mirror subrequest, `@grpc_pass` and `@dubbo_pass` copy `r->headers_in`
# instead of reading `$var_x_forwarded_*` the way `location /` does through
# `proxy_set_header`. They therefore observe whether `handle_x_forwarded_headers`
# wrote the X-Forwarded-* request headers, which it only does for a request that
# carried a forgeable value. The mirror stands in for all three here because it
# is the one that can be driven over plain HTTP.
use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();
log_level('info');

add_block_preprocessor(sub {
    my ($block) = @_;

    my $http_config = <<_EOC_;
    server {
        listen 1986;
        server_tokens off;

        location / {
            content_by_lua_block {
                local core = require("apisix.core")
                local headers = ngx.req.get_headers()
                core.log.warn("mirror x-forwarded-proto: ",
                              tostring(headers["x-forwarded-proto"]),
                              ", x-forwarded-host: ",
                              tostring(headers["x-forwarded-host"]),
                              ", x-forwarded-port: ",
                              tostring(headers["x-forwarded-port"]))
                ngx.say("mirrored")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests;

__DATA__

=== TEST 1: a request carrying no X-Forwarded-* leaves the mirror with none either
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
--- apisix_yaml
routes:
  -
    id: 1
    uri: /hello
    plugins:
        proxy-mirror:
            host: "http://127.0.0.1:1986"
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /hello
--- response_body
hello world
--- error_log
mirror x-forwarded-proto: nil, x-forwarded-host: nil, x-forwarded-port: nil



=== TEST 2: a forged X-Forwarded-* is neutralized for the mirror as well
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
--- apisix_yaml
routes:
  -
    id: 1
    uri: /hello
    plugins:
        proxy-mirror:
            host: "http://127.0.0.1:1986"
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /hello
--- more_headers
X-Forwarded-Proto: https
X-Forwarded-Host: evil.com
X-Forwarded-Port: 8443
--- response_body
hello world
--- error_log
mirror x-forwarded-proto: http, x-forwarded-host: localhost, x-forwarded-port: 1984
