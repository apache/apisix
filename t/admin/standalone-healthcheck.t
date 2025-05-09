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
    # restarts cause the memory cache to be emptied, don't do this
    $ENV{TEST_NGINX_FORCE_RESTART_ON_TEST} = 0;
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
use_hup();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->yaml_config) {
        $block->set_value("yaml_config", <<'EOF');
deployment:
    role: traditional
    role_traditional:
        config_provider: yaml
    admin:
        admin_key:
            - name: admin
              key: edd1c9f034335f136f87ad84b625c8f1
              role: admin
apisix:
  status_standalone:
    ip: 127.0.0.1
    port: 7085
EOF
    }

    if (!defined $block->no_error_log) {
        $block->set_value("no_error_log", "");
    }
});

run_tests();

__DATA__

=== TEST 1: send /healthcheck
--- config 
location /t {
       content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local core = require("apisix.core")

            local ok, err = httpc:connect({
                scheme = "http",
                host = "127.0.0.1",
                port = 7085,
            })

            if not ok then
                ngx.status = 500
                ngx.say(err)
                return
            end

            local params = {
                method = "GET",
            }

            local res, err = httpc:request(params)
            if not res then
                ngx.status = 500
                ngx.say(err)
                return
            end
            ngx.say(res.body)
        }
}
--- response_body
hello world
