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

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: Compatibility testing
--- config
    location /t {
        content_by_lua_block {
            local rfc5424 = require("apisix.utils.rfc5424")
            local structured_data = {
                {name = "project", value = "apisix.apache.org"},
                {name = "logstore", value = "apisix.apache.org"},
                {name = "access-key-id", value = "apisix.sls.logger"},
                {name = "access-key-secret", value = "BD274822-96AA-4DA6-90EC-15940FB24444"}
            }
            local data = rfc5424.encode("SYSLOG", "INFO", "localhost", "apisix",
                                                123456, "hello world", structured_data)
            ngx.say(data)
        }
    }
--- response_body eval
qr/<46>1.*localhost apisix 123456 - \[logservice project=\"apisix\.apache\.org\" logstore=\"apisix\.apache\.org\" access-key-id=\"apisix\.sls\.logger\" access-key-secret=\"BD274822-96AA-4DA6-90EC-15940FB24444\"\] hello world/



=== TEST 2: No structured data test
--- config
    location /t {
        content_by_lua_block {
            local rfc5424 = require("apisix.utils.rfc5424")
            local data = rfc5424.encode("SYSLOG", "INFO", "localhost", "apisix",
                                                123456, "hello world")
            ngx.say(data)
        }
    }
--- response_body eval
qr/<46>1.*localhost apisix 123456 - - hello world/



=== TEST 3: No host and appname test
--- config
    location /t {
        content_by_lua_block {
            local rfc5424 = require("apisix.utils.rfc5424")
            local data = rfc5424.encode("SYSLOG", "INFO", nil, nil,
                                                123456, "hello world")
            ngx.say(data)
        }
    }
--- response_body eval
qr/<46>1.*- - 123456 - - hello world/
