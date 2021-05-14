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
BEGIN {
    $ENV{CUSTOM_DNS_SERVER} = "[::1]:1053";
}

use t::APISIX 'no_plan';

repeat_each(1);
log_level('debug');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $yaml_config = $block->yaml_config // <<_EOC_;
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
_EOC_

    $block->set_value("yaml_config", $yaml_config);

    my $routes = <<_EOC_;
routes:
  -
    uri: /hello
    upstream_id: 1
#END
_EOC_

    $block->set_value("apisix_yaml", $block->apisix_yaml . $routes);
});

run_tests();

__DATA__

=== TEST 1: AAAA
--- listen_ipv6
--- apisix_yaml
upstreams:
    -
    id: 1
    nodes:
        ipv6.test.local:1980: 1
    type: roundrobin
--- request
GET /hello
--- error_log
connect to [::1]:1053
--- no_error_log
[error]
--- response_body
hello world
