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

=== TEST 1: routes
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /hello
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
            local code, body, res = t.test('/v1/routes',
                ngx.HTTP_GET)
            res = json.decode(res)
            if res[1] then
                local data = {}
                data.uris = res[1].value.uris
                data.upstream = res[1].value.upstream
                ngx.say(json.encode(data))
            end
        }
    }
--- response_body
{"upstream":{"hash_on":"vars","nodes":[{"host":"127.0.0.1","port":1980,"weight":1}],"pass_host":"pass","scheme":"http","type":"roundrobin"},"uris":["/hello"]}



=== TEST 2: get route with id 1
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /hello
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
            local code, body, res = t.test('/v1/route/1',
                ngx.HTTP_GET)
            res = json.decode(res)
            if res then
                local data = {}
                data.uris = res.value.uris
                data.upstream = res.value.upstream
                ngx.say(json.encode(data))
            end
        }
    }
--- response_body
{"upstream":{"hash_on":"vars","nodes":[{"host":"127.0.0.1","port":1980,"weight":1}],"pass_host":"pass","scheme":"http","type":"roundrobin"},"uris":["/hello"]}



=== TEST 3: routes with invalid id
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /hello
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
            local code, body, res = t.test('/v1/route/2',
                ngx.HTTP_GET)
            local data = {}
            data.status = code
            ngx.say(json.encode(data))
            return
        }
    }
--- response_body
{"status":404}
