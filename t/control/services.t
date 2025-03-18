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
no_long_string();
no_root_location();
no_shuffle();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->yaml_config) {
        my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

        $block->set_value("yaml_config", $yaml_config);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: services
--- apisix_yaml
services:
  -
    id: 200
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local code, body, res = t.test('/v1/services',
                ngx.HTTP_GET)
            res = json.decode(res)
            if res[1] then
                local data = {}
                data.id = res[1].value.id
                data.plugins = res[1].value.plugins
                data.upstream = res[1].value.upstream
                ngx.say(json.encode(data))
            end
            return
        }
    }
--- response_body
{"id":"200","upstream":{"hash_on":"vars","nodes":[{"host":"127.0.0.1","port":1980,"weight":1}],"pass_host":"pass","scheme":"http","type":"roundrobin"}}



=== TEST 2: multiple services
--- apisix_yaml
services:
  -
    id: 200
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      type: roundrobin
  -
    id: 201
    upstream:
      nodes:
        "127.0.0.2:1980": 1
      type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local code, body, res = t.test('/v1/services',
                ngx.HTTP_GET)
            res = json.decode(res)
            local g_data = {}
            for _, r in core.config_util.iterate_values(res) do
                local data = {}
                data.id = r.value.id
                data.plugins = r.value.plugins
                data.upstream = r.value.upstream
                core.table.insert(g_data, data)
            end
            ngx.say(json.encode(g_data))
            return
        }
    }
--- response_body
[{"id":"200","upstream":{"hash_on":"vars","nodes":[{"host":"127.0.0.1","port":1980,"weight":1}],"pass_host":"pass","scheme":"http","type":"roundrobin"}},{"id":"201","upstream":{"hash_on":"vars","nodes":[{"host":"127.0.0.2","port":1980,"weight":1}],"pass_host":"pass","scheme":"http","type":"roundrobin"}}]



=== TEST 3:  get service with id 5
--- apisix_yaml
services:
  -
    id: 5
    plugins:
      limit-count:
        count: 2
        time_window: 60
        rejected_code: 503
        key: remote_addr
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local code, body, res = t.test('/v1/service/5',
                ngx.HTTP_GET)
            res = json.decode(res)
            if res then
                local data = {}
                data.id = res.value.id
                data.plugins = res.value.plugins
                data.upstream = res.value.upstream
                ngx.say(json.encode(data))
            end
            return
        }
    }
--- response_body
{"id":"5","plugins":{"limit-count":{"_meta":{},"allow_degradation":false,"count":2,"key":"remote_addr","key_type":"var","policy":"local","rejected_code":503,"show_limit_quota_header":true,"sync_interval":-1,"time_window":60}},"upstream":{"hash_on":"vars","nodes":[{"host":"127.0.0.1","port":1980,"weight":1}],"pass_host":"pass","scheme":"http","type":"roundrobin"}}



=== TEST 4: services with invalid id
--- apisix_yaml
services:
  -
    id: 1
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local code, body, res = t.test('/v1/service/2',
                ngx.HTTP_GET)
            local data = {}
            data.status = code
            ngx.say(json.encode(data))
            return
        }
    }
--- response_body
{"status":404}
