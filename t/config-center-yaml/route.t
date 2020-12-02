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
log_level('info');
no_root_location();
no_shuffle();

our $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
_EOC_

run_tests();

__DATA__

=== TEST 1: sanity
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    id: 1
    uri: /hello
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
use config_center: yaml
--- no_error_log
[error]



=== TEST 2: route:uri + host (missing host, not hit)
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    id: 1
    uri: /hello
    host: foo.com
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /hello
--- error_code: 404
--- error_log
use config_center: yaml
--- no_error_log
[error]



=== TEST 3: route:uri + host
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    id: 1
    uri: /hello
    host: foo.com
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- more_headers
host: foo.com
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 4: route with bad plugin
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    id: 1
    uri: /hello
    plugins:
        proxy-rewrite:
            uri: 1
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /hello
--- error_code: 404
--- error_log
property "uri" validation failed



=== TEST 5: ignore unknown plugin
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    id: 1
    uri: /hello
    plugins:
        x-rewrite:
            uri: 1
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 6: route with bad plugin, radixtree_host_uri
--- yaml_config
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
    router:
        http: "radixtree_host_uri"
--- apisix_yaml
routes:
  -
    id: 1
    uri: /hello
    plugins:
        proxy-rewrite:
            uri: 1
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /hello
--- error_code: 404
--- error_log
property "uri" validation failed



=== TEST 7: fix route with default value
--- yaml_config
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
    router:
        http: "radixtree_host_uri"
--- apisix_yaml
routes:
  -
    id: 1
    uri: /hello
    plugins:
        uri-blocker:
            block_rules:
                - /h*
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /hello
--- error_code: 403



=== TEST 8: invalid route, bad vars operator
--- yaml_config
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
    router:
        http: "radixtree_host_uri"
--- apisix_yaml
routes:
  -
    id: 1
    uri: /hello
    vars:
        - remote_addr
        - =
        - 1
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /hello
--- error_code: 404
