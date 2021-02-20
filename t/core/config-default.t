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
no_root_location();

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local encode_json = require("toolkit.json").encode
            local config = require("apisix.core").config.local_conf()

            ngx.say("node_listen: ", config.apisix.node_listen)
            ngx.say("stream_proxy: ", encode_json(config.apisix.stream_proxy))
            ngx.say("admin_key: ", encode_json(config.apisix.admin_key))
        }
    }
--- request
GET /t
--- response_body
node_listen: 1984
stream_proxy: {"tcp":[9100]}
admin_key: null



=== TEST 2: wrong type: expect: number, but got: string
--- yaml_config
apisix:
  node_listen: xxxx
--- must_die
--- error_log
failed to parse yaml config: failed to merge, path[apisix->node_listen] expect: number, but got: string



=== TEST 3: use `null` means delete
--- yaml_config
apisix:
  admin_key: null
--- config
  location /t {
    content_by_lua_block {
        local encode_json = require("toolkit.json").encode
        local config = require("apisix.core").config.local_conf()

        ngx.say("admin_key: ", encode_json(config.apisix.admin_key))
    }
}
--- request
GET /t
--- response_body
admin_key: null



=== TEST 4: use `~` means delete
--- yaml_config
apisix:
  admin_key: ~
--- config
  location /t {
    content_by_lua_block {
        local encode_json = require("toolkit.json").encode
        local config = require("apisix.core").config.local_conf()

        ngx.say("admin_key: ", encode_json(config.apisix.admin_key))
    }
}
--- request
GET /t
--- response_body
admin_key: null



=== TEST 5: support listen multiple ports with array
--- yaml_config
apisix:
  node_listen:
    - 1985
    - 1986
--- config
  location /t {
    content_by_lua_block {
        local encode_json = require("toolkit.json").encode
        local config = require("apisix.core").config.local_conf()

        ngx.say("node_listen: ", encode_json(config.apisix.node_listen))
    }
}
--- request
GET /t
--- response_body
node_listen: [1985,1986]
--- no_error_log
[error]



=== TEST 6: support listen multiple ports with array table
--- yaml_config
apisix:
  node_listen:
    - port: 1985
      enable_http2: true
    - port: 1986
      enable_http2: true
--- config
  location /t {
    content_by_lua_block {
        local encode_json = require("toolkit.json").encode
        local config = require("apisix.core").config.local_conf()

        ngx.say("node_listen: ", encode_json(config.apisix.node_listen))
    }
}
--- request
GET /t
--- response_body
node_listen: [{"enable_http2":true,"port":1985},{"enable_http2":true,"port":1986}]
--- no_error_log
[error]
