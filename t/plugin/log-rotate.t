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
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $user_yaml_config = <<_EOC_;
apisix:
  node_listen: 1984

plugins:                          # plugin list
  - log-rotate

plugin_attr:
  log-rotate:
    interval: 1
    max_kept: 3
_EOC_

    $block->set_value("yaml_config", $user_yaml_config);
});

run_tests;

__DATA__

=== TEST 1: log rotate
--- config
    location /t {
        content_by_lua_block {
            ngx.log(ngx.ERR, "start xxxxxx")
            ngx.sleep(2.5)

            local lfs = require("lfs")
            for file in lfs.dir(ngx.config.prefix() .. "/logs/") do
                ngx.say(file)
            end
        }
    }
--- request
GET /t
--- response_body_like eval
qr/\_error\.log[\s\S]*\_access\.log/
--- no_error_log
[error]



=== TEST 2: in current log
--- config
    location /t {
        content_by_lua_block {
            ngx.log(ngx.WARN, "start xxxxxx")
            ngx.sleep(0.1)
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]
--- error_log
start xxxxxx
