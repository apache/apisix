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
worker_connections(256);
no_root_location();
no_shuffle();

our $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
    router:
        http: 'radixtree_host_uri'
    admin_key: null
_EOC_

run_tests();

__DATA__

=== TEST 1: test.com
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /server_port
    host: test.com
    upstream:
        nodes:
            "127.0.0.1:1981": 1
        type: roundrobin
  -
    uri: /server_port
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END

--- request
GET /server_port
--- more_headers
Host: test.com
--- response_body eval
qr/1981/
--- error_log
use config_center: yaml
--- no_error_log
[error]



=== TEST 2: *.test.com + uri
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /server_port
    host: *.test.com
    upstream:
        nodes:
            "127.0.0.1:1981": 1
        type: roundrobin
  -
    uri: /server_port
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END

--- request
GET /server_port
--- more_headers
Host: www.test.com
--- response_body eval
qr/1981/
--- error_log
use config_center: yaml
--- no_error_log
[error]



=== TEST 3: *.test.com + /*
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /*
    host: *.test.com
    upstream:
        nodes:
            "127.0.0.1:1981": 1
        type: roundrobin
  -
    uri: /server_port
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END

--- request
GET /server_port
--- more_headers
Host: www.test.com
--- response_body eval
qr/1981/
--- error_log
use config_center: yaml
--- no_error_log
[error]



=== TEST 4: filter_func(not match)
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /*
    host: *.test.com
    filter_func: "function(vars) return vars.arg_name == 'json' end"
    upstream:
        nodes:
            "127.0.0.1:1981": 1
        type: roundrobin
  -
    uri: /server_port
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END

--- request
GET /server_port?name=unknown
--- more_headers
Host: www.test.com
--- response_body eval
qr/1980/
--- error_log
use config_center: yaml
--- no_error_log
[error]



=== TEST 5: filter_func(match)
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /*
    host: *.test.com
    filter_func: "function(vars) return vars.arg_name == 'json' end"
    upstream:
        nodes:
            "127.0.0.1:1981": 1
        type: roundrobin
  -
    uri: /server_port
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END

--- request
GET /server_port?name=json
--- more_headers
Host: www.test.com
--- response_body eval
qr/1981/
--- error_log
use config_center: yaml
--- no_error_log
[error]
