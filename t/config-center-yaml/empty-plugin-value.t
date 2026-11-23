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

    my $yaml_config = $block->yaml_config // <<_EOC_;
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

    $block->set_value("yaml_config", $yaml_config);
});

run_tests();

__DATA__

=== TEST 1: every empty plugin value and empty _meta belongs to its own resource
--- apisix_yaml
routes:
  - id: 1
    uri: /hello
    plugins:
      cors:
      proxy-rewrite:
        uri: /hello
        _meta:
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      type: roundrobin
  - id: 2
    uri: /hello1
    plugins:
      cors:
      proxy-rewrite:
        uri: /hello1
        _meta:
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local http = require("resty.http")
            for _, uri in ipairs({"/hello", "/hello1"}) do
                local res = http.new():request_uri("http://127.0.0.1:1984" .. uri)
                ngx.say(uri, " ", res.status)
            end

            local confs = {}
            for _, item in ipairs(core.config.fetch_created_obj("/routes").values) do
                local plugins = item.value.plugins
                for _, name in ipairs({"cors", "proxy-rewrite"}) do
                    ngx.say(item.value.id, " ", name, " parent: ",
                            plugins[name]._meta._parent.resource_key)
                    confs[name] = confs[name] or {}
                    core.table.insert(confs[name], plugins[name])
                end
            end
            ngx.say("own cors conf: ", confs.cors[1] ~= confs.cors[2])
            ngx.say("own _meta: ", confs["proxy-rewrite"][1]._meta
                                   ~= confs["proxy-rewrite"][2]._meta)
        }
    }
--- request
GET /t
--- response_body
/hello 200
/hello1 200
1 cors parent: /routes/1
1 proxy-rewrite parent: /routes/1
2 cors parent: /routes/2
2 proxy-rewrite parent: /routes/2
own cors conf: true
own _meta: true



=== TEST 2: a workflow action with an empty _meta loads and runs
--- apisix_yaml
routes:
  - id: 1
    uri: /hello
    plugins:
      workflow:
        rules:
          - actions:
              - - return
                - code: 403
                  _meta:
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      type: roundrobin
#END
--- request
GET /hello
--- error_code: 403



=== TEST 3: the defaults an empty plugin value gets stay out of every other empty value
--- apisix_yaml
consumers:
  - username: jack
    plugins:
      jwt-auth:
        key: user-key
        secret: my-secret-key
routes:
  - id: 1
    uri: /hello
    plugins:
      key-auth:
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      type: roundrobin
  - id: 2
    uri: /hello1
    plugins:
      jwt-auth:
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      type: roundrobin
#END
--- config
    location /t {
        content_by_lua_block {
            local jwt = require("resty.jwt")
            local token = jwt:sign("my-secret-key", {
                header = {typ = "JWT", alg = "HS256"},
                payload = {key = "user-key", exp = ngx.time() + 3600},
            })
            local http = require("resty.http")
            local res = http.new():request_uri("http://127.0.0.1:1984/hello1",
                                               {headers = {Authorization = token}})
            ngx.say("jwt in Authorization: ", res.status)
            local null = require("lyaml").null
            ngx.say("lyaml null carries key-auth defaults: ", null.header ~= nil)
        }
    }
--- request
GET /t
--- response_body
jwt in Authorization: 200
lyaml null carries key-auth defaults: false
