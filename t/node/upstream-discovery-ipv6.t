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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->yaml_config) {
        $block->set_value("yaml_config", <<_EOC_);
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_
    }

    # a discovery node reaches the balancer without going through the schema check
    # or the bracketing the Admin API applies, so a bare IPv6 host arrives here raw
    $block->set_value("listen_ipv6", 1);

    if ($block->apisix_yaml) {
        $block->set_value("apisix_yaml", $block->apisix_yaml . <<_EOC_);
upstreams:
    - service_name: mock
      discovery_type: mock
      type: least_conn
      id: 1
#END
_EOC_
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: single bare-IPv6 node from discovery, least_conn
--- apisix_yaml
routes:
  - uris:
      - /hello
    upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.init").discovery
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "::1", port = 1980, weight = 1},
                    }
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res = assert(http.new():request_uri(uri, {keepalive = false}))
            ngx.say(res.status)
            ngx.print(res.body)
        }
    }
--- response_body
200
hello world
--- no_error_log
attempt to concatenate



=== TEST 2: multiple bare-IPv6 nodes from discovery, least_conn
--- apisix_yaml
routes:
  - uris:
      - /hello
    upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.init").discovery
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "::1", port = 1980, weight = 1},
                        {host = "0:0:0:0:0:0:0:1", port = 1980, weight = 1},
                    }
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res = assert(http.new():request_uri(uri, {keepalive = false}))
            ngx.say(res.status)
            ngx.print(res.body)
        }
    }
--- response_body
200
hello world
--- no_error_log
attempt to concatenate



=== TEST 3: a discovery re-fetch of the same bare-IPv6 nodes is not seen as a change
--- apisix_yaml
routes:
  - uris:
      - /hello
    upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            local discovery = require("apisix.discovery.init").discovery
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "::1", port = 1980, weight = 1},
                    }
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            for _ = 1, 3 do
                assert(http.new():request_uri(uri, {keepalive = false}))
            end
            ngx.say("ok")
        }
    }
--- response_body
ok
--- grep_error_log eval
qr/create_obj_fun\(\): upstream nodes:/
--- grep_error_log_out
create_obj_fun(): upstream nodes:



=== TEST 4: bare-IPv6 node that already has port and priority is still bracketed
--- apisix_yaml
routes:
  - uris:
      - /hello
    upstream_id: 1
--- config
    location /t {
        content_by_lua_block {
            -- port and priority both set, so the node skips the port/priority fill.
            -- Only the IPv6 branch of the clone condition can trigger here
            local discovery = require("apisix.discovery.init").discovery
            discovery.mock = {
                nodes = function()
                    return {
                        {host = "::1", port = 1980, weight = 1, priority = 0},
                    }
                end
            }
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res = assert(http.new():request_uri(uri, {keepalive = false}))
            ngx.say(res.status)
            ngx.print(res.body)
        }
    }
--- response_body
200
hello world
--- no_error_log
attempt to concatenate
