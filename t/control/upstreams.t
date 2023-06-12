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

=== TEST 1: dump all upstreams
--- apisix_yaml
upstreams:
    -
        id: 1
        nodes:
            "127.0.0.1:8001": 1
        type: roundrobin
    -
        id: 2
        nodes:
            "127.0.0.1:8002": 1
        type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local code, body, res = t.test('/v1/upstreams',
                ngx.HTTP_GET)
            res = json.decode(res)
            if res[2] and table.getn(res) == 2 then
                local data = {}
                data.nodes = res[2].value.nodes
                ngx.say(json.encode(data))
            end
        }
    }
--- response_body
{"nodes":[{"host":"127.0.0.1","port":8002,"weight":1}]}



=== TEST 2: dump specific upstream with id 1
--- apisix_yaml
upstreams:
    -
        id: 1
        nodes:
            "127.0.0.1:8001": 1
        type: roundrobin
    -
        id: 2
        nodes:
            "127.0.0.1:8002": 1
        type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local code, body, res = t.test('/v1/upstream/1',
                ngx.HTTP_GET)
            res = json.decode(res)
            if res then
                local data = {}
                data.nodes = res.value.nodes
                ngx.say(json.encode(data))
            end
        }
    }
--- response_body
{"nodes":[{"host":"127.0.0.1","port":8001,"weight":1}]}



=== TEST 3: upstreams with invalid id
--- apisix_yaml
upstreams:
    -
        id: 1
        nodes:
            "127.0.0.1:8001": 1
        type: roundrobin
    -
        id: 2
        nodes:
            "127.0.0.1:8002": 1
        type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin")
            local code, body, res = t.test('/v1/upstream/3',
                ngx.HTTP_GET)
            local data = {}
            data.status = code
            ngx.say(json.encode(data))
            return
        }
    }
--- response_body
{"status":404}
