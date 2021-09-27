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

no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: Server header for admin API
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            uri = ngx.var.scheme .. "://" .. ngx.var.server_addr
                  .. ":" .. ngx.var.server_port .. "/apisix/admin/routes"
            local res, err = httpc:request_uri(uri)
            ngx.say(res.headers["Server"])
        }
    }
--- response_body eval
qr/APISIX\//



=== TEST 2: Server header for admin API without token
--- yaml_config
apisix:
  node_listen: 1984
  enable_server_tokens: false
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            uri = ngx.var.scheme .. "://" .. ngx.var.server_addr
                  .. ":" .. ngx.var.server_port .. "/apisix/admin/routes"
            local res, err = httpc:request_uri(uri)
            ngx.say(res.headers["Server"])
        }
    }
--- response_body
APISIX
