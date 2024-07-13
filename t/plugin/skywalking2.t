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

add_block_preprocessor(sub {
    my ($block) = @_;

    my $extra_yaml_config = <<_EOC_;
plugins:
    - example-plugin
    - key-auth
    - skywalking
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    $block;
});

repeat_each(1);
no_long_string();
no_root_location();
log_level("info");

run_tests;

__DATA__

=== TEST 1: using http should give security warning
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.skywalking")
            local ok, err = plugin.check_schema({endpoint_addr = "http://127.0.0.1:12800"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- error_log
Using skywalking endpoint_addr with no TLS is a security risk



=== TEST 2: using https should not give security warning
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.skywalking")
            local ok, err = plugin.check_schema({endpoint_addr = "https://127.0.0.1:12800"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
Using skywalking endpoint_addr with no TLS is a security risk
