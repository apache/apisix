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
    router:
        http: 'radixtree_host_uri'
    admin_key: null
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->yaml_config) {
        $block->set_value("yaml_config", $yaml_config);
    }
});

run_tests();

__DATA__

=== TEST 1: hit routes(priority: 1 + priority: 2)
--- apisix_yaml
routes:
  -
    uri: /server_port
    host: test.com
    upstream:
        nodes:
            "127.0.0.1:1981": 1
        type: roundrobin
    priority: 1
  -
    uri: /server_port
    host: test.com
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
    priority: 2
#END

--- request
GET /server_port
--- more_headers
Host: test.com
--- response_body eval
qr/1980/
--- error_log
use config_provider: yaml



=== TEST 2: hit routes(priority: 2 + priority: 1)
--- apisix_yaml
routes:
  -
    uri: /server_port
    host: test.com
    upstream:
        nodes:
            "127.0.0.1:1981": 1
        type: roundrobin
    priority: 2
  -
    uri: /server_port
    host: test.com
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
    priority: 1
#END

--- request
GET /server_port
--- more_headers
Host: test.com
--- response_body eval
qr/1981/
--- error_log
use config_provider: yaml



=== TEST 3: hit routes(priority: default_value + priority: 1)
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
    host: test.com
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
    priority: 1
#END

--- request
GET /server_port
--- more_headers
Host: test.com
--- response_body eval
qr/1980/
--- error_log
use config_provider: yaml



=== TEST 4: hit routes(priority: 1 + priority: default_value)
--- apisix_yaml
routes:
  -
    uri: /server_port
    host: test.com
    upstream:
        nodes:
            "127.0.0.1:1981": 1
        type: roundrobin
    priority: 1
  -
    uri: /server_port
    host: test.com
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
use config_provider: yaml
