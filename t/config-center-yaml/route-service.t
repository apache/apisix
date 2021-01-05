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

=== TEST 1: hit route
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
    -
        uri: /hello
        service_id: 1
        id: 1
services:
    -
        id: 1
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



=== TEST 2: not found service
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
    -
        uri: /hello
        id: 1
        service_id: 1111
services:
    -
        id: 1
        upstream:
            nodes:
                "127.0.0.1:1980": 1
            type: roundrobin
#END
--- request
GET /hello
--- error_code: 404
--- error_log
failed to fetch service configuration by id: 1111



=== TEST 3: service upstream priority
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
    -
        id: 1
        uri: /hello
        service_id: 1
services:
    -
        id: 1
        upstream:
            nodes:
                "127.0.0.1:1977": 1
            type: roundrobin
        upstream_id: 1
upstreams:
    -
        id: 1
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



=== TEST 4: route service upstream priority
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
    -
        id: 1
        uri: /hello
        service_id: 1
        upstream:
            nodes:
                "127.0.0.1:1980": 1
            type: roundrobin
services:
    -
        id: 1
        upstream:
            nodes:
                "127.0.0.1:1977": 1
            type: roundrobin
upstreams:
    -
        id: 1
        nodes:
            "127.0.0.1:1977": 1
        type: roundrobin
#END
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 5: route service upstream by upstream_id priority
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
    -
        id: 1
        uri: /hello
        service_id: 1
        upstream:
            nodes:
                "127.0.0.1:1977": 1
            type: roundrobin
        upstream_id: 1
services:
    -
        id: 1
        upstream:
            nodes:
                "127.0.0.1:1977": 1
            type: roundrobin
upstreams:
    -
        id: 1
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



=== TEST 6: route service upstream priority
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
    -
        id: 1
        uri: /hello
        service_id: 1
        upstream:
            nodes:
                "127.0.0.1:1980": 1
            type: roundrobin
services:
    -
        id: 1
        upstream:
            nodes:
                "127.0.0.1:1977": 1
            type: roundrobin
        upstream_id: 1
upstreams:
    -
        id: 1
        nodes:
            "127.0.0.1:1977": 1
        type: roundrobin
#END
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 7: two routes with the same service
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
    - uris:
        - /hello
      service_id: 1
      id: 1
      plugins:
        response-rewrite:
            body: "hello\n"
    - uris:
        - /world
      service_id: 1
      id: 2
      plugins:
        response-rewrite:
            body: "world\n"
services:
    -
        id: 1
        upstream:
            nodes:
                "127.0.0.1:1980": 1
            type: roundrobin
#END
--- request
GET /hello
--- response_body
hello
--- no_error_log
[error]



=== TEST 8: service with bad plugin
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
    -
        id: 1
        uri: /hello
        service_id: 1
services:
    -
        id: 1
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



=== TEST 9: fix service with default value
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
    -
        id: 1
        uri: /hello
        service_id: 1
services:
    -
        id: 1
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
