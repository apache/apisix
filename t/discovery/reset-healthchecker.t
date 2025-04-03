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
no_root_location();
no_shuffle();
workers(1);




add_block_preprocessor(sub {
    my ($block) = @_;
    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
    if ($block->apisix_yaml) {
        my $upstream = <<_EOC_;
upstreams:
    - service_name: mock
      discovery_type: mock
      type: roundrobin
      checks:
        active:
          http_path: /
          timeout: 1
          unhealthy:
            tcp_failures: 30
            interval: 1
          healthy:
            interval: 1
      id: 1
#END
_EOC_

        $block->set_value("apisix_yaml", $block->apisix_yaml . $upstream);
    }
});

run_tests();

__DATA__

=== TEST 1: Validate healthchecker recreation on DNS node changes
--- http_config
server {
    listen 3000 ;
    location / {
      return 200 'ok';
    }
}
--- apisix_yaml
routes:
  -
    uris:
        - /
    upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local discovery = require("apisix.discovery.init").discovery
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.1", port = 3000, weight = 50},
                        {host = "127.0.0.1", port = 8000, weight = 50},
                    }
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.sleep(5)
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.1", port = 3000, weight = 1}
                    }
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.say(res.body)
            ngx.sleep(5)
        }
    }
--- request
GET /t
--- response_body
ok
--- timeout: 22
--- no_error_log
unhealthy TCP increment (10/30)
