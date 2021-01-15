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
no_root_location();
no_shuffle();

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

    if ($block->apisix_yaml) {
        my $upstream = <<_EOC_;
upstreams:
    - service_name: mock
      discovery_type: mock
      type: roundrobin
      id: 1
      checks:
        active:
            http_path: "/status"
            host: 127.0.0.1
            port: 1988
            healthy:
                interval: 1
                successes: 1
            unhealthy:
                interval: 1
                http_failures: 1
#END
_EOC_

        $block->set_value("apisix_yaml", $block->apisix_yaml . $upstream);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: sanity
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.init").discovery
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.1", port = 1980, weight = 1},
                        {host = "0.0.0.0", port = 1980, weight = 1},
                    }
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})

            ngx.sleep(0.5)

            ngx.say(res.status)
        }
    }
--- grep_error_log eval
qr/unhealthy TCP increment \(1\/2\) for '127.0.0.1\([^)]+\)'/
--- grep_error_log_out
unhealthy TCP increment (1/2) for '127.0.0.1(127.0.0.1:1988)'
unhealthy TCP increment (1/2) for '127.0.0.1(0.0.0.0:1988)'



=== TEST 2: create new checker when nodes change
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.init").discovery
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.1", port = 1980, weight = 1},
                        {host = "0.0.0.0", port = 1980, weight = 1},
                    }
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.sleep(0.5)

            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.1", port = 1980, weight = 1},
                        {host = "127.0.0.2", port = 1980, weight = 1},
                        {host = "127.0.0.3", port = 1980, weight = 1},
                    }
                end
            }
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.say(res.status)
        }
    }
--- grep_error_log eval
qr/create new checker: table/
--- grep_error_log_out
create new checker: table
create new checker: table



=== TEST 3: don't create new checker when nodes don't change
--- apisix_yaml
routes:
  -
    uris:
        - /hello
    upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.init").discovery
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "127.0.0.1", port = 1980, weight = 1},
                        {host = "0.0.0.0", port = 1980, weight = 1},
                    }
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.sleep(0.5)

            discovery.mock = {
                nodes = function()
                    return {
                        {host = "0.0.0.0", port = 1980, weight = 1},
                        {host = "127.0.0.1", port = 1980, weight = 1},
                    }
                end
            }
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {method = "GET", keepalive = false})
            ngx.say(res.status)
        }
    }
--- grep_error_log eval
qr/create new checker: table/
--- grep_error_log_out
create new checker: table
