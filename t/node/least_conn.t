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

repeat_each(2);
log_level('info');
no_root_location();
worker_connections(1024);
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

    my $route = <<_EOC_;
routes:
    - 
    upstream_id: 1
    uris:
        - /mysleep
#END
_EOC_

    $block->set_value("apisix_yaml", $block->apisix_yaml . $route);

    if (!$block->request) {
        $block->set_value("request", "GET /mysleep?seconds=0.1");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: select highest weight
--- apisix_yaml
upstreams:
    -
    id: 1
    type: least_conn
    nodes:
        "127.0.0.1:1980": 2
        "127.0.0.1:1981": 1
--- grep_error_log eval
qr/proxy request to \S+ while connecting to upstream/
--- grep_error_log_out
proxy request to 127.0.0.1:1980 while connecting to upstream



=== TEST 2: select least conn
--- ONLY
--- apisix_yaml
upstreams:
    -
    id: 1
    type: least_conn
    nodes:
        "127.0.0.1:1980": 3
        "0.0.0.0:1980": 2
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
--- grep_error_log eval
qr/proxy request to \S+ while connecting to upstream/
--- grep_error_log_out
proxy request to 127.0.0.1:1980 while connecting to upstream
proxy request to 0.0.0.0:1980 while connecting to upstream
proxy request to 127.0.0.1:1980 while connecting to upstream



=== TEST 3: retry
--- apisix_yaml
upstreams:
    -
    id: 1
    type: least_conn
    nodes:
        "127.0.0.1:1999": 2
        "127.0.0.1:1980": 1
--- error_log
connect() failed
--- grep_error_log eval
qr/proxy request to \S+ while connecting to upstream/
--- grep_error_log_out
proxy request to 127.0.0.1:1999 while connecting to upstream
proxy request to 127.0.0.1:1980 while connecting to upstream



=== TEST 4: retry all nodes, failed
--- apisix_yaml
upstreams:
    -
    id: 1
    type: least_conn
    nodes:
        "127.0.0.1:1999": 2
        "0.0.0.0:1999": 1
--- error_log
connect() failed
--- error_code: 502
--- grep_error_log eval
qr/proxy request to \S+ while connecting to upstream/
--- grep_error_log_out
proxy request to 127.0.0.1:1999 while connecting to upstream
proxy request to 0.0.0.0:1999 while connecting to upstream
