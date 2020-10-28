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
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $user_yaml_config = <<_EOC_;
plugins:                          # plugin list
  - error-log-logger

plugin_attr:
  error-log-logger:
    host: "227.0.0.1"
    port: 1999
    level: "warn"
    timeout: 3
    batch_max_size: 1
_EOC_

    $block->set_value("yaml_config", $user_yaml_config);
});

run_tests;

__DATA__

=== TEST 1: test unreachable server
--- config
    location /tg {
        content_by_lua_block {
            local core = require("apisix.core")
            core.log.warn("this is a warning message for test.\n")
        }
    }
--- request
GET /tg
--- response_body
--- error_log eval
qr/Batch Processor\[error-log-logger\] failed to process/
--- wait: 3
