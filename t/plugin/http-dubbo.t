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
no_shuffle();
no_root_location();
add_block_preprocessor(sub {
    my ($block) = @_;
    my $yaml_config = $block->yaml_config // <<_EOC_;
apisix:
    node_listen: 1984
    enable_admin: false
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

    $block->set_value("yaml_config", $yaml_config);
});

run_tests;

__DATA__

=== TEST 1:  test_pojo
--- apisix_yaml
upstreams:
    - nodes:
        - host: 127.0.0.1
          port: 30880
          weight: 1
      type: roundrobin
      id: 1
routes:
  -
    uri: /t
    plugins:
        http-dubbo:
            service_name: org.apache.dubbo.backend.DubboSerializationTestService
            params_type_desc: Lorg/apache/dubbo/backend/PoJo;
            serialized: true
            method: testPoJo
            service_version: 1.0.0
    upstream_id: 1
#END
--- request
POST /t
{"aBoolean":true,"aByte":1,"aDouble":1.1,"aFloat":1.2,"aInt":2,"aLong":3,"aShort":4,"aString":"aa","acharacter":"a","stringMap":{"key":"value"},"strings":["aa","bb"]}
--- response_body chomp
{"aBoolean":true,"aByte":1,"aDouble":1.1,"aFloat":1.2,"aInt":2,"aLong":3,"aShort":4,"aString":"aa","acharacter":"a","stringMap":{"key":"value"},"strings":["aa","bb"]}



=== TEST 2:  test_pojos
--- apisix_yaml
upstreams:
    - nodes:
        - host: 127.0.0.1
          port: 30880
          weight: 1
      type: roundrobin
      id: 1
routes:
  -
    uri: /t
    plugins:
        http-dubbo:
            service_name: org.apache.dubbo.backend.DubboSerializationTestService
            params_type_desc: "[Lorg/apache/dubbo/backend/PoJo;"
            serialized: true
            method: testPoJos
            service_version: 1.0.0
    upstream_id: 1
#END
--- request
POST /t
[{"aBoolean":true,"aByte":1,"aDouble":1.1,"aFloat":1.2,"aInt":2,"aLong":3,"aShort":4,"aString":"aa","acharacter":"a","stringMap":{"key":"value"},"strings":["aa","bb"]}]
--- response_body chomp
[{"aBoolean":true,"aByte":1,"aDouble":1.1,"aFloat":1.2,"aInt":2,"aLong":3,"aShort":4,"aString":"aa","acharacter":"a","stringMap":{"key":"value"},"strings":["aa","bb"]}]



=== TEST 2:  test_timeout
--- apisix_yaml
upstreams:
    - nodes:
        - host: 127.0.0.1
          port: 30881
          weight: 1
      type: roundrobin
      id: 1
routes:
  -
    uri: /t
    plugins:
        http-dubbo:
            service_name: org.apache.dubbo.backend.DubboSerializationTestService
            params_type_desc: "[Lorg/apache/dubbo/backend/PoJo;"
            serialized: true
            method: testPoJos
            service_version: 1.0.0
            connect_timeout：100
            read_timeout: 100
            send_timeout: 100
    upstream_id: 1
#END
--- config
    location /t {
        content_by_lua_block {

            local code, body = t('/t',
                ngx.HTTP_GET
            )
            if code == 502 then
                ngx.say("passed")
            else
                ngx.say("fail")
            end

        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2:  test_void
--- apisix_yaml
upstreams:
    - nodes:
        - host: 127.0.0.1
          port: 30880
          weight: 1
      type: roundrobin
      id: 1
routes:
  -
    uri: /t
    plugins:
        http-dubbo:
            service_name: org.apache.dubbo.backend.DubboSerializationTestService
            params_type_desc:
            serialized: true
            method: testVoid
            service_version: 1.0.0
    upstream_id: 1
#END
--- config
    location /t {
        content_by_lua_block {

            local code, body = t('/t',
                ngx.HTTP_GET
            )
            if code == 200 then
                ngx.say("passed")
            else
                ngx.say("fail")
            end

        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2:  test_fail
--- apisix_yaml
upstreams:
    - nodes:
        - host: 127.0.0.1
          port: 30880
          weight: 1
      type: roundrobin
      id: 1
routes:
  -
    uri: /t
    plugins:
        http-dubbo:
            service_name: org.apache.dubbo.backend.DubboSerializationTestService
            params_type_desc:
            serialized: true
            method: testFailure
            service_version: 1.0.0
    upstream_id: 1
#END
--- config
    location /t {
        content_by_lua_block {

            local code, body = t('/t',
                ngx.HTTP_GET
            )
            if code == 500 then
                ngx.say("passed")
            else
                ngx.say("fail")
            end

        }
    }
--- request
GET /t
--- response_body
passed
