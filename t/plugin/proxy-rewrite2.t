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
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $yaml_config = $block->yaml_config // <<_EOC_;
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

    $block->set_value("yaml_config", $yaml_config);

    if (!$block->request) {
        $block->set_value("request", "GET /hello");
    }
});

run_tests;

__DATA__

=== TEST 1: access $upstream_uri before proxy-rewrite
--- apisix_yaml
global_rules:
  -
    id: 1
    plugins:
      serverless-pre-function:
        phase: rewrite
        functions:
            - "return function() ngx.log(ngx.WARN, 'serverless [', ngx.var.upstream_uri, ']') end"
routes:
  -
    id: 1
    uri: /hello
    plugins:
        proxy-rewrite:
            uri: "/plugin_proxy_rewrite"
    upstream_id: 1
upstreams:
  -
    id: 1
    nodes:
        "127.0.0.1:1980": 1
    type: roundrobin
#END
--- error_log
serverless []
--- response_body
uri: /plugin_proxy_rewrite
host: localhost
scheme: http



=== TEST 2: default X-Forwarded-Proto
--- apisix_yaml
routes:
  -
    id: 1
    uri: /echo
    upstream_id: 1
upstreams:
  -
    id: 1
    nodes:
        "127.0.0.1:1980": 1
    type: roundrobin
#END
--- request
GET /echo
--- response_headers
X-Forwarded-Proto: http



=== TEST 3: pass X-Forwarded-Proto
--- apisix_yaml
routes:
  -
    id: 1
    uri: /echo
    upstream_id: 1
upstreams:
  -
    id: 1
    nodes:
        "127.0.0.1:1980": 1
    type: roundrobin
#END
--- request
GET /echo
--- more_headers
X-Forwarded-Proto: https
--- response_headers
X-Forwarded-Proto: https



=== TEST 4: customize X-Forwarded-Proto
--- apisix_yaml
routes:
  -
    id: 1
    uri: /echo
    plugins:
        proxy-rewrite:
            headers:
                X-Forwarded-Proto: https
    upstream_id: 1
upstreams:
  -
    id: 1
    nodes:
        "127.0.0.1:1980": 1
    type: roundrobin
#END
--- request
GET /echo
--- more_headers
X-Forwarded-Proto: grpc
--- response_headers
X-Forwarded-Proto: https



=== TEST 5: make sure X-Forwarded-Proto hit the `core.request.header` cache
--- apisix_yaml
routes:
  -
    id: 1
    uri: /echo
    plugins:
        serverless-pre-function:
            phase: rewrite
            functions:
              - return function(conf, ctx) local core = require("apisix.core"); ngx.log(ngx.ERR, core.request.header(ctx, "host")); end
        proxy-rewrite:
            headers:
                X-Forwarded-Proto: https-rewrite
    upstream_id: 1
upstreams:
  -
    id: 1
    nodes:
        "127.0.0.1:1980": 1
    type: roundrobin
#END
--- request
GET /echo
--- more_headers
X-Forwarded-Proto: grpc
--- response_headers
X-Forwarded-Proto: https-rewrite
--- error_log
localhost



=== TEST 6: pass duplicate X-Forwarded-Proto
--- apisix_yaml
routes:
  -
    id: 1
    uri: /echo
    upstream_id: 1
upstreams:
  -
    id: 1
    nodes:
        "127.0.0.1:1980": 1
    type: roundrobin
#END
--- request
GET /echo
--- more_headers
X-Forwarded-Proto: http
X-Forwarded-Proto: grpc
--- response_headers
X-Forwarded-Proto: http, grpc



=== TEST 7: customize X-Forwarded-Port
--- apisix_yaml
routes:
  -
    id: 1
    uri: /echo
    plugins:
        proxy-rewrite:
            headers:
                X-Forwarded-Port: 10080
    upstream_id: 1
upstreams:
  -
    id: 1
    nodes:
        "127.0.0.1:1980": 1
    type: roundrobin
#END
--- request
GET /echo
--- more_headers
X-Forwarded-Port: 8080
--- response_headers
X-Forwarded-Port: 10080
