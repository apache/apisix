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

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    $block;
});

run_tests;

__DATA__

=== TEST 1: get plugins' name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require('cjson')
            local code, _, body = t("/apisix/admin/plugins/list", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local tab = json.decode(body)
            for _, v in ipairs(tab) do
                ngx.say(v)
            end
        }
    }

--- response_body
real-ip
ai
client-control
proxy-control
request-id
zipkin
ext-plugin-pre-req
fault-injection
mocking
serverless-pre-function
cors
ip-restriction
ua-restriction
referer-restriction
csrf
uri-blocker
request-validation
chaitin-waf
multi-auth
openid-connect
cas-auth
authz-casbin
authz-casdoor
wolf-rbac
ldap-auth
hmac-auth
basic-auth
jwt-auth
jwe-decrypt
key-auth
consumer-restriction
attach-consumer-label
forward-auth
opa
authz-keycloak
proxy-cache
body-transformer
ai-request-rewrite
ai-prompt-guard
ai-prompt-template
ai-prompt-decorator
ai-rag
ai-aws-content-moderation
proxy-mirror
proxy-rewrite
workflow
api-breaker
limit-conn
limit-count
limit-req
ai-proxy
ai-proxy-multi
gzip
server-info
traffic-split
redirect
response-rewrite
degraphql
kafka-proxy
grpc-transcode
grpc-web
http-dubbo
public-api
prometheus
datadog
loki-logger
elasticsearch-logger
echo
loggly
http-logger
splunk-hec-logging
skywalking-logger
google-cloud-logging
sls-logger
tcp-logger
kafka-logger
rocketmq-logger
syslog
udp-logger
file-logger
clickhouse-logger
tencent-cloud-cls
inspect
example-plugin
aws-lambda
azure-functions
openwhisk
openfunction
serverless-post-function
ext-plugin-post-req
ext-plugin-post-resp



=== TEST 2: invalid plugin
--- request
GET /apisix/admin/plugins/asdf
--- error_code: 404
--- response_body
{"error_msg":"plugin not found in subsystem http"}



=== TEST 3: get plugin schema
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugins/limit-req',
                ngx.HTTP_GET,
                nil,
                [[
                {"type":"object","required":["rate","burst","key"],"properties":{"rate":{"type":"number","exclusiveMinimum":0},"key_type":{"type":"string","enum":["var","var_combination"],"default":"var"},"burst":{"type":"number","minimum":0},"nodelay":{"type":"boolean","default":false},"key":{"type":"string"},"rejected_code":{"type":"integer","minimum":200,"maximum":599,"default":503},"rejected_msg":{"type":"string","minLength":1},"allow_degradation":{"type":"boolean","default":false}}}
                ]]
                )

            ngx.status = code
        }
    }



=== TEST 4: get plugin node-status schema
--- extra_yaml_config
plugins:
    - node-status
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugins/node-status',
                ngx.HTTP_GET,
                nil,
                [[
{"properties":{},"type":"object"}
                ]]
                )

            ngx.status = code
        }
    }



=== TEST 5: get plugin prometheus schema
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugins/prometheus',
                ngx.HTTP_GET,
                nil,
                [[
{"properties":{},"type":"object"}
                ]]
                )

            ngx.status = code
        }
    }



=== TEST 6: get plugin basic-auth schema
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugins/basic-auth',
                ngx.HTTP_GET,
                nil,
                [[
{"properties":{},"title":"work with route or service object","type":"object"}
                ]]
                )

            ngx.status = code
        }
    }



=== TEST 7: get plugin basic-auth schema by schema_type
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/plugins/basic-auth?schema_type=consumer',
                ngx.HTTP_GET,
                nil,
                [[
{"title":"work with consumer object","required":["username","password"],"properties":{"username":{"type":"string"},"password":{"type":"string"}},"type":"object"}
                ]]
                )

            ngx.status = code
        }
    }



=== TEST 8: confirm the name, priority, schema, type and version of plugin
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, message, res = t('/apisix/admin/plugins?all=true',
                ngx.HTTP_GET
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            for k, v in pairs(res) do
                if k == "example-plugin" then
                    ngx.say(json.encode(v))
                end
            end
        }
    }
--- response_body eval
qr/\{"metadata_schema":\{"properties":\{"ikey":\{"minimum":0,"type":"number"\},"skey":\{"type":"string"\}\},"required":\["ikey","skey"\],"type":"object"\},"priority":0,"schema":\{"\$comment":"this is a mark for our injected plugin schema","properties":\{"_meta":\{"additionalProperties":false,"properties":\{"disable":\{"type":"boolean"\},"error_response":\{"oneOf":\[\{"type":"string"\},\{"type":"object"\}\]\},"filter":\{"description":"filter determines whether the plugin needs to be executed at runtime","type":"array"\},"pre_function":\{"description":"function to be executed in each phase before execution of plugins. The pre_function will have access to two arguments: `conf` and `ctx`.","type":"string"\},"priority":\{"description":"priority of plugins by customized order","type":"integer"\}\},"type":"object"\},"i":\{"minimum":0,"type":"number"\},"ip":\{"type":"string"\},"port":\{"type":"integer"\},"s":\{"type":"string"\},"t":\{"minItems":1,"type":"array"\}\},"required":\["i"\],"type":"object"\},"version":0.1\}/



=== TEST 9: confirm the plugin of auth type
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, message, res = t('/apisix/admin/plugins?all=true',
                ngx.HTTP_GET
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            local auth_plugins = {}
            for k, v in pairs(res) do
                if v.type == "auth" then
                    local plugin = {}
                    plugin.name = k
                    plugin.priority = v.priority
                    table.insert(auth_plugins, plugin)
                end
            end

            table.sort(auth_plugins, function(l, r)
                return l.priority > r.priority
            end)
            ngx.say(json.encode(auth_plugins))
        }
    }
--- response_body eval
qr/\[\{"name":"multi-auth","priority":2600\},\{"name":"wolf-rbac","priority":2555\},\{"name":"ldap-auth","priority":2540\},\{"name":"hmac-auth","priority":2530\},\{"name":"basic-auth","priority":2520\},\{"name":"jwt-auth","priority":2510\},\{"name":"jwe-decrypt","priority":2509\},\{"name":"key-auth","priority":2500\}\]/



=== TEST 10: confirm the consumer_schema of plugin
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, message, res = t('/apisix/admin/plugins?all=true',
                ngx.HTTP_GET
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            local consumer_schema
            for k, v in pairs(res) do
                if k == "basic-auth" then
                    consumer_schema = v.consumer_schema
                end
            end
            ngx.say(json.encode(consumer_schema))
        }
    }
--- response_body eval
qr/\{"encrypt_fields":\["password"\],"properties":\{"password":\{"type":"string"\},"username":\{"type":"string"\}\},"required":\["username","password"\],"title":"work with consumer object","type":"object"\}/



=== TEST 11: confirm the name, priority, schema, type and version of stream plugin
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, message, res = t('/apisix/admin/plugins?all=true&subsystem=stream',
                ngx.HTTP_GET
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            for k, v in pairs(res) do
                if k == "limit-conn" then
                    ngx.say(json.encode(v))
                end
            end
        }
    }
--- response_body
{"priority":1003,"schema":{"$comment":"this is a mark for our injected plugin schema","properties":{"_meta":{"additionalProperties":false,"properties":{"disable":{"type":"boolean"},"error_response":{"oneOf":[{"type":"string"},{"type":"object"}]},"filter":{"description":"filter determines whether the plugin needs to be executed at runtime","type":"array"},"pre_function":{"description":"function to be executed in each phase before execution of plugins. The pre_function will have access to two arguments: `conf` and `ctx`.","type":"string"},"priority":{"description":"priority of plugins by customized order","type":"integer"}},"type":"object"},"burst":{"minimum":0,"type":"integer"},"conn":{"exclusiveMinimum":0,"type":"integer"},"default_conn_delay":{"exclusiveMinimum":0,"type":"number"},"key":{"type":"string"},"key_type":{"default":"var","enum":["var","var_combination"],"type":"string"},"only_use_default_delay":{"default":false,"type":"boolean"}},"required":["conn","burst","default_conn_delay","key"],"type":"object"},"version":0.1}



=== TEST 12: confirm the scope of plugin
--- extra_yaml_config
plugins:
  - batch-requests
  - error-log-logger
  - server-info
  - example-plugin
  - node-status
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, message, res = t('/apisix/admin/plugins?all=true',
                ngx.HTTP_GET
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            res = json.decode(res)
            local global_plugins = {}
            for k, v in pairs(res) do
                if v.scope == "global" then
                    global_plugins[k] = v.scope
                end
            end
            ngx.say(json.encode(global_plugins))
        }
    }
--- response_body
{"batch-requests":"global","error-log-logger":"global","node-status":"global","server-info":"global"}



=== TEST 13: check with wrong plugin subsystem
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local _, message, _ = t('/apisix/admin/plugins?subsystem=asdf',
                ngx.HTTP_GET
            )
            ngx.say(message)
        }
    }
--- response_body eval
qr/\{"error_msg":"unsupported subsystem: asdf"\}/



=== TEST 14: check with right plugin in wrong subsystem
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local _, message, _ = t('/apisix/admin/plugins/http-logger?subsystem=stream',
                ngx.HTTP_GET
            )
            ngx.say(message)
        }
    }
--- response_body eval
qr/\{"error_msg":"plugin not found in subsystem stream"\}/



=== TEST 15: check with right plugin in right subsystem
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local _, _ , message = t('/apisix/admin/plugins/http-logger?subsystem=http',
                ngx.HTTP_GET
            )
            ngx.say(message)
        }
    }
--- response_body eval
qr/this is a mark for our injected plugin schema/
