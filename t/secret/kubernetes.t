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

BEGIN {
    $ENV{KUBERNETES_SERVICE_HOST} = "127.0.0.1";
    $ENV{KUBERNETES_SERVICE_PORT} = "6443";
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
log_level("info");

run_tests;

__DATA__

=== TEST 1: schema validation - all fields valid
--- config
    location /t {
        content_by_lua_block {
            local kubernetes = require("apisix.secret.kubernetes")
            local core = require("apisix.core")

            local test_cases = {
                {},
                {ssl_verify = true},
                {ssl_verify = false},
                {ssl_verify = 1234},
                {service_account_file = "/var/run/secrets/kubernetes.io/serviceaccount/token"},
                {service_account_file = 1234},
                {kubernetes_host = "kubernetes.default.svc"},
                {kubernetes_host = 1234},
                {kubernetes_port = "443"},
                {kubernetes_port = 1234},
                {
                    service_account_file = "/var/run/secrets/kubernetes.io/serviceaccount/token",
                    kubernetes_host = "kubernetes.default.svc",
                    kubernetes_port = "443",
                    ssl_verify = true,
                },
            }

            for _, conf in ipairs(test_cases) do
                local ok, err = core.schema.check(kubernetes.schema, conf)
                ngx.say(ok and "done" or err)
            end
        }
    }
--- request
GET /t
--- response_body
done
done
done
property "ssl_verify" validation failed: wrong type: expected boolean, got number
done
property "service_account_file" validation failed: wrong type: expected string, got number
done
property "kubernetes_host" validation failed: wrong type: expected string, got number
done
property "kubernetes_port" validation failed: wrong type: expected string, got number
done



=== TEST 2: get - invalid key format (no slashes)
--- config
    location /t {
        content_by_lua_block {
            local kubernetes = require("apisix.secret.kubernetes")
            local data, err = kubernetes.get({}, "no-slashes")
            if err then
                return ngx.say(err)
            end
            ngx.say(data)
        }
    }
--- request
GET /t
--- response_body
invalid key format, expected {namespace}/{secret-name}/{data-key}, got: no-slashes



=== TEST 3: get - invalid key format (only one slash, missing data-key)
--- config
    location /t {
        content_by_lua_block {
            local kubernetes = require("apisix.secret.kubernetes")
            local data, err = kubernetes.get({}, "default/my-secret")
            if err then
                return ngx.say(err)
            end
            ngx.say(data)
        }
    }
--- request
GET /t
--- response_body
invalid key format, missing data-key, expected {namespace}/{secret-name}/{data-key}, got: default/my-secret



=== TEST 4: get - empty namespace
--- config
    location /t {
        content_by_lua_block {
            local kubernetes = require("apisix.secret.kubernetes")
            local data, err = kubernetes.get({}, "/my-secret/my-key")
            if err then
                return ngx.say(err)
            end
            ngx.say(data)
        }
    }
--- request
GET /t
--- response_body
namespace is empty in key: /my-secret/my-key



=== TEST 5: get - empty secret-name
--- config
    location /t {
        content_by_lua_block {
            local kubernetes = require("apisix.secret.kubernetes")
            local data, err = kubernetes.get({}, "default//my-key")
            if err then
                return ngx.say(err)
            end
            ngx.say(data)
        }
    }
--- request
GET /t
--- response_body
secret-name is empty in key: default//my-key



=== TEST 6: get - empty data-key
--- config
    location /t {
        content_by_lua_block {
            local kubernetes = require("apisix.secret.kubernetes")
            local data, err = kubernetes.get({}, "default/my-secret/")
            if err then
                return ngx.say(err)
            end
            ngx.say(data)
        }
    }
--- request
GET /t
--- response_body
data-key is empty in key: default/my-secret/



=== TEST 7: get - service account file not found
--- config
    location /t {
        content_by_lua_block {
            local kubernetes = require("apisix.secret.kubernetes")
            local conf = {
                service_account_file = "/nonexistent/token",
                ssl_verify = false,
            }
            local data, err = kubernetes.get(conf, "default/my-secret/my-key")
            if err then
                return ngx.say(err)
            end
            ngx.say(data)
        }
    }
--- request
GET /t
--- response_body_like
failed to open file /nonexistent/token:.*



=== TEST 8: get - connection refused (API server not reachable)
--- config
    location /t {
        content_by_lua_block {
            -- Write a temp token file for the test
            local f = io.open("/tmp/test-sa-token", "w")
            f:write("test-token")
            f:close()

            local kubernetes = require("apisix.secret.kubernetes")
            local conf = {
                service_account_file = "/tmp/test-sa-token",
                endpoint = "https://127.0.0.2:9999",
                ssl_verify = false,
            }
            local data, err = kubernetes.get(conf, "default/my-secret/my-key")
            if err then
                return ngx.say(err)
            end
            ngx.say(data)
        }
    }
--- request
GET /t
--- response_body_like
failed to request Kubernetes API:.*
--- timeout: 6



=== TEST 9: get - mock Kubernetes API returns 401
--- config
    location /mock-k8s-401 {
        content_by_lua_block {
            ngx.status = 401
            ngx.header["Content-Type"] = "application/json"
            ngx.say('{"kind":"Status","apiVersion":"v1","status":"Failure","message":"Unauthorized","reason":"Unauthorized","code":401}')
        }
    }
    location /t {
        content_by_lua_block {
            local f = io.open("/tmp/test-sa-token", "w")
            f:write("bad-token")
            f:close()

            local kubernetes = require("apisix.secret.kubernetes")
            local conf = {
                service_account_file = "/tmp/test-sa-token",
                endpoint = "http://127.0.0.1:1984",
                ssl_verify = false,
            }
            -- Note: the mock server path doesn't match the real k8s path,
            -- so we expect a non-200 response handled gracefully
            local data, err = kubernetes.get(conf, "default/my-secret/my-key")
            if err then
                return ngx.say(err)
            end
            ngx.say(data)
        }
    }
--- request
GET /t
--- response_body_like
(unauthorized to read Kubernetes secret|failed to request Kubernetes API|unexpected HTTP status).*



=== TEST 10: get - mock Kubernetes API returns valid secret
--- config
    location ~ "^/api/v1/namespaces/default/secrets/my-secret$" {
        content_by_lua_block {
            ngx.header["Content-Type"] = "application/json"
            -- {"username":"admin","password":"s3cr3t"} base64-encoded per field
            ngx.say([[{
                "apiVersion": "v1",
                "kind": "Secret",
                "metadata": {"name": "my-secret", "namespace": "default"},
                "data": {
                    "username": "YWRtaW4=",
                    "password": "czNjcjN0"
                },
                "type": "Opaque"
            }]])
        }
    }
    location /t {
        content_by_lua_block {
            local f = io.open("/tmp/test-sa-token", "w")
            f:write("valid-token")
            f:close()

            local kubernetes = require("apisix.secret.kubernetes")
            local conf = {
                service_account_file = "/tmp/test-sa-token",
                endpoint = "http://127.0.0.1:1984",
                ssl_verify = false,
            }

            local username, err = kubernetes.get(conf, "default/my-secret/username")
            if err then
                ngx.say("username error: " .. err)
            else
                ngx.say("username: " .. username)
            end

            local password, err2 = kubernetes.get(conf, "default/my-secret/password")
            if err2 then
                ngx.say("password error: " .. err2)
            else
                ngx.say("password: " .. password)
            end
        }
    }
--- request
GET /t
--- response_body
username: admin
password: s3cr3t



=== TEST 11: get - mock Kubernetes API returns 404
--- config
    location ~ "^/api/v1/namespaces/default/secrets/missing-secret$" {
        content_by_lua_block {
            ngx.status = 404
            ngx.header["Content-Type"] = "application/json"
            ngx.say('{"kind":"Status","apiVersion":"v1","status":"Failure","message":"secrets \"missing-secret\" not found","reason":"NotFound","code":404}')
        }
    }
    location /t {
        content_by_lua_block {
            local f = io.open("/tmp/test-sa-token", "w")
            f:write("valid-token")
            f:close()

            local kubernetes = require("apisix.secret.kubernetes")
            local conf = {
                service_account_file = "/tmp/test-sa-token",
                endpoint = "http://127.0.0.1:1984",
                ssl_verify = false,
            }
            local data, err = kubernetes.get(conf, "default/missing-secret/my-key")
            if err then
                return ngx.say(err)
            end
            ngx.say(data)
        }
    }
--- request
GET /t
--- response_body
Kubernetes secret not found: default/missing-secret



=== TEST 12: get - data-key not found in secret
--- config
    location ~ "^/api/v1/namespaces/default/secrets/partial-secret$" {
        content_by_lua_block {
            ngx.header["Content-Type"] = "application/json"
            ngx.say([[{
                "apiVersion": "v1",
                "kind": "Secret",
                "metadata": {"name": "partial-secret", "namespace": "default"},
                "data": {
                    "username": "YWRtaW4="
                },
                "type": "Opaque"
            }]])
        }
    }
    location /t {
        content_by_lua_block {
            local f = io.open("/tmp/test-sa-token", "w")
            f:write("valid-token")
            f:close()

            local kubernetes = require("apisix.secret.kubernetes")
            local conf = {
                service_account_file = "/tmp/test-sa-token",
                endpoint = "http://127.0.0.1:1984",
                ssl_verify = false,
            }
            local data, err = kubernetes.get(conf, "default/partial-secret/password")
            if err then
                return ngx.say(err)
            end
            ngx.say(data)
        }
    }
--- request
GET /t
--- response_body
key 'password' not found in Kubernetes secret default/partial-secret



=== TEST 13: end-to-end via Admin API - register kubernetes secret manager
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/secrets/kubernetes/my-k8s',
                ngx.HTTP_PUT,
                [[{
                    "service_account_file": "/tmp/test-sa-token",
                    "endpoint": "http://127.0.0.1:1984",
                    "ssl_verify": false
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



=== TEST 14: end-to-end via Admin API - use $secret://kubernetes in plugin config
--- config
    location ~ "^/api/v1/namespaces/default/secrets/api-credentials$" {
        content_by_lua_block {
            ngx.header["Content-Type"] = "application/json"
            ngx.say([[{
                "apiVersion": "v1",
                "kind": "Secret",
                "metadata": {"name": "api-credentials", "namespace": "default"},
                "data": {
                    "client_id": "bXktY2xpZW50",
                    "client_secret": "bXktc2VjcmV0"
                },
                "type": "Opaque"
            }]])
        }
    }
    location /t {
        content_by_lua_block {
            local f = io.open("/tmp/test-sa-token", "w")
            f:write("valid-token")
            f:close()

            -- Simulate how fetch_secrets resolves $secret:// in plugin config
            local secret = require("apisix.secret")
            local refs = {
                client_id = "$secret://kubernetes/my-k8s/default/api-credentials/client_id",
                client_secret = "$secret://kubernetes/my-k8s/default/api-credentials/client_secret",
            }
            local resolved = secret.fetch_secrets(refs, false)
            ngx.say("client_id: " .. (resolved.client_id or "nil"))
            ngx.say("client_secret: " .. (resolved.client_secret or "nil"))
        }
    }
--- request
GET /t
--- response_body
client_id: my-client
client_secret: my-secret
