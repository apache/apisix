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

repeat_each(2); # repeat each test to ensure after_balance is called correctly
log_level('info');
no_root_location();
worker_connections(1024);
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if ($block->apisix_yaml) {
        if (!$block->yaml_config) {
            my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
_EOC_

            $block->set_value("yaml_config", $yaml_config);
        }
    }

    $block->set_value("stream_enable", 1);

    if (!$block->stream_request) {
        $block->set_value("stream_request", "mmm");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: sanity
--- apisix_yaml
stream_routes:
    -
    id: 1
    upstream:
        type: least_conn
        nodes:
        - host: 127.0.0.1
          port: 1979
          weight: 2
          priority: 1
        - host: 127.0.0.2
          port: 1979
          weight: 1
          priority: 1
        - host: 127.0.0.3
          port: 1979
          weight: 2
          priority: 0
        - host: 127.0.0.4
          port: 1979
          weight: 1
          priority: 0
        - host: 127.0.0.1
          port: 1995
          weight: 2
          priority: -1
#END
--- stream_response
hello world
--- error_log
connect() failed
failed to get server from current priority 1, try next one
failed to get server from current priority 0, try next one
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out
proxy request to 127.0.0.1:1979
proxy request to 127.0.0.2:1979
proxy request to 127.0.0.3:1979
proxy request to 127.0.0.4:1979
proxy request to 127.0.0.1:1995



=== TEST 2: default priority is 0
--- apisix_yaml
stream_routes:
    -
    id: 1
    upstream:
        type: least_conn
        nodes:
        - host: 127.0.0.1
          port: 1979
          weight: 2
          priority: 1
        - host: 127.0.0.2
          port: 1979
          weight: 1
          priority: 1
        - host: 127.0.0.3
          port: 1979
          weight: 2
        - host: 127.0.0.4
          port: 1979
          weight: 1
        - host: 127.0.0.1
          port: 1995
          weight: 2
          priority: -1
#END
--- stream_response
hello world
--- error_log
connect() failed
failed to get server from current priority 1, try next one
failed to get server from current priority 0, try next one
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out
proxy request to 127.0.0.1:1979
proxy request to 127.0.0.2:1979
proxy request to 127.0.0.3:1979
proxy request to 127.0.0.4:1979
proxy request to 127.0.0.1:1995



=== TEST 3: fix priority for nonarray nodes
--- apisix_yaml
stream_routes:
    -
    id: 1
    upstream:
        type: roundrobin
        nodes:
            "127.0.0.1:1995": 1
            "127.0.0.2:1995": 1
#END
--- stream_response
hello world
