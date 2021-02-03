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
# unit test for cli module
use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();
log_level("info");

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: local_dns_resolver
--- config
    location /t {
        content_by_lua_block {
            local local_dns_resolver = require("apisix.cli.ops").local_dns_resolver
            local json_encode = require("toolkit.json").encode
            ngx.say(json_encode(local_dns_resolver("$TEST_NGINX_HTML_DIR/resolv.conf")))
        }
    }
--- user_files
>>> resolv.conf
# This file was automatically generated.
nameserver 172.27.0.1

nameserver fe80::215:5dff:fec5:8e1d
--- response_body
["172.27.0.1","fe80::215:5dff:fec5:8e1d"]
