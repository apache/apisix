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
EOF
    }

    if (!defined $block->no_error_log) {
        $block->set_value("no_error_log", "");
    }
});

run_tests();

__DATA__

=== TEST 1: test
--- timeout: 15
--- max_size: 204800
--- exec
cd t && pnpm test admin/standalone.spec.ts 2>&1
--- no_error_log
failed to execute the script with status
--- response_body eval
qr/PASS admin\/standalone.spec.ts/



=== TEST 2: configure route
--- config
    location /t {} # force the worker to restart by changing the configuration
--- request
PUT /apisix/admin/configs?conf_version=101
{"routes":[{"id":"r1","uri":"/r1","upstream":{"nodes":{"127.0.0.1:1980":1},"type":"roundrobin"},"plugins":{"proxy-rewrite":{"uri":"/hello"}}}]}
--- more_headers
X-API-KEY: edd1c9f034335f136f87ad84b625c8f1
--- error_code: 202



=== TEST 3: test route
--- config
    location /t1 {}
--- request
GET /r1
--- error_code: 200
--- response_body
hello world



=== TEST 4: remove route
--- config
    location /t2 {}
--- request
PUT /apisix/admin/configs?conf_version=102
{}
--- more_headers
X-API-KEY: edd1c9f034335f136f87ad84b625c8f1
--- error_code: 202



=== TEST 5: test non-exist route
--- config
    location /t3 {}
--- request
GET /r1
--- error_code: 404
