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

log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    # A negative threshold makes every worker take the configuration loaded by
    # the master as stale, which is what a worker respawned after the master
    # has been running for longer than worker_startup_time_threshold sees.
    my $yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
  proxy_mode: http&stream
  stream_proxy:
    tcp:
      - 9100
  enable_resolv_search_opt: false
  worker_startup_time_threshold: -1
_EOC_

    $block->set_value("yaml_config", $yaml_config);
});

run_tests();

__DATA__

=== TEST 1: set stream route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/stream_routes/1',
                ngx.HTTP_PUT,
                [[{
                    "remote_addr": "127.0.0.1",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1995": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: a worker that finds the loaded configuration stale still proxies stream traffic
--- stream_request
mmm
--- stream_response
hello world
--- error_log
reloading the full configuration from etcd for this new worker
discarding the stale configuration for this new worker
--- no_error_log
API disabled in the context of init_worker_by_lua*
[error]
