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

repeat_each(2); # repeat each test to ensure after_balance is called correctly
log_level('info');
no_root_location();
worker_connections(1024);
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if ($block->apisix_yaml) {
        if (!$block->yaml_config) {
            my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
_EOC_

            $block->set_value("yaml_config", $yaml_config);
        }

        my $route = <<_EOC_;
routes:
    -
    upstream_id: 1
    uris:
        - /hello
        - /mysleep
#END
_EOC_

        $block->set_value("apisix_yaml", $block->apisix_yaml . $route);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /hello");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: sanity
--- apisix_yaml
upstreams:
    -
    id: 1
    type: least_conn
    nodes:
        - host: 127.0.0.1
          port: 1979
          weight: 2
          priority: 1
        - host: 127.0.0.2
          port: 1979
          weight: 1
          priority: 1
        - host: 127.0.0.3
          port: 1979
          weight: 2
          priority: 0
        - host: 127.0.0.4
          port: 1979
          weight: 1
          priority: 0
        - host: 127.0.0.1
          port: 1980
          weight: 2
          priority: -1
--- response_body
hello world
--- error_log
connect() failed
failed to get server from current priority 1, try next one
failed to get server from current priority 0, try next one
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out
proxy request to 127.0.0.1:1979
proxy request to 127.0.0.2:1979
proxy request to 127.0.0.3:1979
proxy request to 127.0.0.4:1979
proxy request to 127.0.0.1:1980



=== TEST 2: all failed
--- apisix_yaml
upstreams:
    -
    id: 1
    type: least_conn
    nodes:
        - host: 127.0.0.1
          port: 1979
          weight: 2
          priority: 1
        - host: 127.0.0.2
          port: 1979
          weight: 1
          priority: 0
        - host: 127.0.0.1
          port: 1979
          weight: 2
          priority: -1
--- error_code: 502
--- error_log
connect() failed
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out
proxy request to 127.0.0.1:1979
proxy request to 127.0.0.2:1979
proxy request to 127.0.0.1:1979



=== TEST 3: default priority is zero
--- apisix_yaml
upstreams:
    -
    id: 1
    type: least_conn
    nodes:
        - host: 127.0.0.1
          port: 1979
          weight: 2
          priority: 1
        - host: 127.0.0.2
          port: 1979
          weight: 1
        - host: 127.0.0.1
          port: 1980
          weight: 2
          priority: -1
--- response_body
hello world
--- error_log
connect() failed
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out
proxy request to 127.0.0.1:1979
proxy request to 127.0.0.2:1979
proxy request to 127.0.0.1:1980



=== TEST 4: least_conn
--- apisix_yaml
upstreams:
    -
    id: 1
    type: least_conn
    nodes:
        - host: 127.0.0.1
          port: 1979
          weight: 2
          priority: 1
        - host: 127.0.0.1
          port: 1980
          weight: 3
          priority: -1
        - host: 0.0.0.0
          port: 1980
          weight: 2
          priority: -1
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/mysleep?seconds=0.1"

            local t = {}
            for i = 1, 3 do
                local th = assert(ngx.thread.spawn(function(i)
                    local httpc = http.new()
                    local res, err = httpc:request_uri(uri..i, {method = "GET"})
                    if not res then
                        ngx.log(ngx.ERR, err)
                        return
                    end
                end, i))
                table.insert(t, th)
            end
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
            end
        }
    }
--- request
GET /t
--- error_log
connect() failed
--- grep_error_log eval
qr/proxy request to \S+ while connecting to upstream/
--- grep_error_log_out
proxy request to 127.0.0.1:1979 while connecting to upstream
proxy request to 127.0.0.1:1979 while connecting to upstream
proxy request to 127.0.0.1:1979 while connecting to upstream
proxy request to 127.0.0.1:1980 while connecting to upstream
proxy request to 0.0.0.0:1980 while connecting to upstream
proxy request to 127.0.0.1:1980 while connecting to upstream



=== TEST 5: roundrobin
--- apisix_yaml
upstreams:
    -
    id: 1
    type: roundrobin
    nodes:
        - host: 127.0.0.1
          port: 1979
          weight: 2
          priority: 1
        - host: 127.0.0.2
          port: 1979
          weight: 1
          priority: 1
        - host: 127.0.0.3
          port: 1979
          weight: 2
          priority: -1
        - host: 127.0.0.4
          port: 1979
          weight: 1
          priority: -1
--- error_code: 502
--- error_log
connect() failed
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out
proxy request to 127.0.0.1:1979
proxy request to 127.0.0.2:1979
proxy request to 127.0.0.3:1979
proxy request to 127.0.0.4:1979



=== TEST 6: ewma
--- apisix_yaml
upstreams:
    -
    id: 1
    type: ewma
    key: remote_addr
    nodes:
        - host: 127.0.0.1
          port: 1979
          weight: 2
          priority: 1
        - host: 127.0.0.2
          port: 1979
          weight: 1
          priority: 0
        - host: 127.0.0.3
          port: 1979
          weight: 2
          priority: -1
--- error_code: 502
--- error_log
connect() failed
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out
proxy request to 127.0.0.1:1979
proxy request to 127.0.0.2:1979
proxy request to 127.0.0.3:1979



=== TEST 7: chash
--- apisix_yaml
upstreams:
    -
    id: 1
    type: chash
    key: remote_addr
    nodes:
        - host: 127.0.0.1
          port: 1979
          weight: 2
          priority: 1
        - host: 127.0.0.2
          port: 1979
          weight: 1
          priority: 1
        - host: 127.0.0.3
          port: 1979
          weight: 2
          priority: -1
        - host: 127.0.0.4
          port: 1979
          weight: 1
          priority: -1
--- error_code: 502
--- error_log
connect() failed
--- grep_error_log eval
qr/proxy request to \S+/
--- grep_error_log_out
proxy request to 127.0.0.1:1979
proxy request to 127.0.0.2:1979
proxy request to 127.0.0.4:1979
proxy request to 127.0.0.3:1979
