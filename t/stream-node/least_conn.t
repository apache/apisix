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

# every repeat opens a new connection against the same worker, so the balancing
# state built by the previous ones is still there. Without releasing the server
# in the log phase the counts only grow and the picks start to drift away from
# the node with the highest weight.
repeat_each(4);
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if ($block->apisix_yaml && !$block->yaml_config) {
        my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

        $block->set_value("yaml_config", $yaml_config);
    }

    $block->set_value("stream_enable", 1);

    if (!$block->stream_request) {
        $block->set_value("stream_request", "mmm");
    }
});

run_tests();

__DATA__

=== TEST 1: release the finished connection in the stream log phase
--- apisix_yaml
stream_routes:
  - id: 1
    upstream:
        type: least_conn
        nodes:
        - host: 127.0.0.1
          port: 1995
          weight: 3
        - host: 127.0.0.2
          port: 1995
          weight: 1
#END
--- stream_response
hello world
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out
proxy request to 127.0.0.1:1995
