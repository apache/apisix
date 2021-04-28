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
        id: 1
        uri: /hello
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



=== TEST 2: not found upstream
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
    -
        id: 1
        uri: /hello
        upstream_id: 1111
upstreams:
    -
        id: 1
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /hello
--- error_code_like: ^(?:50\d)$
--- error_log
failed to find upstream by id: 1111



=== TEST 3: upstream_id priority upstream
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
    -
        id: 1
        uri: /hello
        upstream_id: 1
        upstream:
            nodes:
                "127.0.0.1:1977": 1
            type: roundrobin
upstreams:
    -
        id: 1
        nodes:
            "127.0.0.1:1981": 1
        type: roundrobin
#END
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 4: enable healthcheck
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
    -
        id: 1
        uri: /hello
        upstream_id: 1
upstreams:
    -
        id: 1
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
        retries: 2
        checks:
            active:
                http_path: "/status"
                healthy:
                    interval: 2
                    successes: 1
#END
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 5: upstream domain
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
    -
        id: 1
        uri: /get
        upstream_id: 1
upstreams:
    -
        id: 1
        nodes:
            "httpbin.org:80": 1
        type: roundrobin
#END
--- request
GET /get
--- error_code: 200
--- no_error_log
[error]



=== TEST 6: upstream hash_on (bad)
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
    -
        id: 1
        uri: /get
        upstream_id: 1
upstreams:
    -
        id: 1
        nodes:
            "httpbin.org:80": 1
        type: chash
        hash_on: header
        key: "$aaa"
#END
--- request
GET /get
--- error_code: 502
--- error_log
invalid configuration: failed to match pattern



=== TEST 7: upstream hash_on (good)
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
    -
        id: 1
        uri: /hello
        upstream_id: 1
upstreams:
    -
        id: 1
        nodes:
            "127.0.0.1:1980": 1
            "127.0.0.2:1980": 1
        type: chash
        hash_on: header
        key: "test"
#END
--- request
GET /hello
--- more_headers
test: one
--- error_log
proxy request to 127.0.0.1:1980
--- no_error_log
[error]
