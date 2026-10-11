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
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->yaml_config) {
        $block->set_value("yaml_config", <<'_EOC_');
deployment:
    role: traditional
    role_traditional:
        config_provider: yaml
    admin:
        admin_key:
            - name: admin
              key: edd1c9f034335f136f87ad84b625c8f1
              role: admin
_EOC_
    }

    $block->set_value("stream_enable", 1);

    if (!$block->stream_request) {
        $block->set_value("stream_request", "mmm");
    }
});

run_tests();

__DATA__

=== TEST 1: stream connection before the first config is pushed
--- error_log
not hit any route
--- no_error_log
attempt to index local 'tab'
