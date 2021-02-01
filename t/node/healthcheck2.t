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

master_on();
repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();
worker_connections(256);

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->yaml_config) {
        my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
_EOC_

        $block->set_value("yaml_config", $yaml_config);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: can't use service_name with nodes
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream_id: 1
upstreams:
    - service_name: abaaba
      discovery_type: eureka
      nodes:
        "127.0.0.1:80": 1
      type: roundrobin
      id: 1
#END
--- error_log
value should match only one schema, but matches both schemas 1 and 2
--- request
GET /hello
--- error_code: 502



=== TEST 2: route + service
--- apisix_yaml
services:
    - id: 1
      upstream:
          type: roundrobin
          nodes:
              "127.0.0.1:1980": 1
              "127.0.0.1:1970": 1
          checks:
              active:
                  http_path: /status
                  host: foo.com
                  healthy:
                      interval: 1
                      successes: 1
                  unhealthy:
                      interval: 1
                      http_failures: 2
routes:
    -
    service_id: 1
    uri: /server_port
#END
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            end

            ngx.sleep(2.5)

            local ports_count = {}
            for i = 1, 12 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
                if not res then
                    ngx.say(err)
                    return
                end

                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- response_body
[{"count":12,"port":"1980"}]
--- grep_error_log eval
qr/\([^)]+\) unhealthy .* for '.*'/
--- grep_error_log_out
(upstream#/services/1) unhealthy TCP increment (1/2) for 'foo.com(127.0.0.1:1970)'
(upstream#/services/1) unhealthy TCP increment (2/2) for 'foo.com(127.0.0.1:1970)'
--- timeout: 10



=== TEST 3: route override service
--- apisix_yaml
services:
    - id: 1
      upstream:
          type: roundrobin
          nodes:
              "127.0.0.2:1980": 1
              "127.0.0.2:1970": 1
          checks:
              active:
                  http_path: /status
                  host: foo.com
                  healthy:
                      interval: 1
                      successes: 1
                  unhealthy:
                      interval: 1
                      http_failures: 2
routes:
    -
    service_id: 1
    uri: /server_port
    upstream:
        type: roundrobin
        nodes:
            "127.0.0.1:1980": 1
            "127.0.0.1:1970": 1
        checks:
            active:
                http_path: /status
                host: foo.com
                healthy:
                    interval: 1
                    successes: 1
                unhealthy:
                    interval: 1
                    http_failures: 2
#END
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/server_port"

            do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            end

            ngx.sleep(2.5)

            local ports_count = {}
            for i = 1, 12 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
                if not res then
                    ngx.say(err)
                    return
                end

                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("toolkit.json").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- response_body
[{"count":12,"port":"1980"}]
--- grep_error_log eval
qr/\([^)]+\) unhealthy .* for '.*'/
--- grep_error_log_out
(upstream#/routes/arr_1) unhealthy TCP increment (1/2) for 'foo.com(127.0.0.1:1970)'
(upstream#/routes/arr_1) unhealthy TCP increment (2/2) for 'foo.com(127.0.0.1:1970)'
--- timeout: 10
