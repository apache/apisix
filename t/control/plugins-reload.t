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
workers(2);

add_block_preprocessor(sub {
    my ($block) = @_;

    $block;
});

run_tests;

__DATA__

=== TEST 1: reload plugins
--- yaml_config
apisix:
    node_listen: 1984
    enable_control: true
    control:
      ip: "127.0.0.1"
      port: 9090
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin")

        local code, body, res = t.test('/v1/plugins/reload',
            ngx.HTTP_PUT)
        ngx.say(res)
        ngx.sleep(1)
    }
}
--- request
GET /t
--- response_body
done
--- error_log
start to hot reload plugins



=== TEST 2: reload plugins when attributes changed
--- yaml_config
apisix:
  node_listen: 1984
  enable_admin: true
  node_listen: 1984
plugins:
    - example-plugin
plugin_attr:
    example-plugin:
        val: 0
--- config
location /t {
    content_by_lua_block {
        local core = require "apisix.core"
        ngx.sleep(0.1)
        local data = [[
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
apisix:
  node_listen: 1984
  enable_control: true
  control:
    ip: "127.0.0.1"
    port: 9090
plugins:
    - example-plugin
plugin_attr:
    example-plugin:
        val: 1
        ]]
        require("lib.test_admin").set_config_yaml(data)

        local t = require("lib.test_admin").test
        local code, _, org_body = t('/v1/plugins/reload',
                                    ngx.HTTP_PUT)

        ngx.status = code
        ngx.say(org_body)
        ngx.sleep(0.1)

        local data = [[
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    admin_key: null
apisix:
  node_listen: 1984
plugins:
    - example-plugin
plugin_attr:
    example-plugin:
        val: 1
        ]]
        require("lib.test_admin").set_config_yaml(data)

        local t = require("lib.test_admin").test
        local code, _, org_body = t('/v1/plugins/reload',
                                    ngx.HTTP_PUT)
        ngx.say(org_body)
        ngx.sleep(0.1)
    }
}
--- request
GET /t
--- response_body
done
done
--- grep_error_log eval
qr/example-plugin get plugin attr val: \d+/
--- grep_error_log_out
example-plugin get plugin attr val: 0
example-plugin get plugin attr val: 0
example-plugin get plugin attr val: 0
example-plugin get plugin attr val: 1
example-plugin get plugin attr val: 1



=== TEST 3: wrong method to reload plugins
--- request
GET /v1/plugins/reload
--- error_code: 404



=== TEST 4: wrong method to reload plugins
--- request
POST /v1/plugins/reload
--- error_code: 404



=== TEST 5: reload plugin with data_plane deployment
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: false
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      type: roundrobin
#END
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin")

        local code, body, res = t.test('/v1/plugins/reload',
            ngx.HTTP_PUT)
        ngx.say(res)
        ngx.sleep(1)
    }
}
--- request
GET /t
--- response_body
done
--- error_log
start to hot reload plugins
