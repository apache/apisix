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

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: add consumer with validate_request_body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "robin",
                    "plugins": {
                        "hmac-auth": {
                            "key_id": "my-access-key",
                            "secret_key": "my-secret-key"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: enable hmac auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "hmac-auth": {
                            "validate_request_body": true,
                            "signed_headers": ["date", "digest"]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 3: missing body digest when validate_request_body is enabled
--- config
    location /t {
        content_by_lua_block {
            local ngx_time = ngx.time
            local ngx_http_time = ngx.http_time
            local core = require("apisix.core")
            local t = require("lib.test_admin")
            local hmac = require("resty.hmac")
            local ngx_encode_base64 = ngx.encode_base64

            local secret_key = "my-secret-key"
            local timestamp = ngx_time()
            local gmt = ngx_http_time(timestamp)
            local key_id = "my-access-key"
            local custom_header_a = "asld$%dfasf"
            local custom_header_b = "23879fmsldfk"
            local body = "{\"name\": \"world\"}"

            local signing_string = {
                 key_id,
                "POST /hello",
                "date: " .. gmt,
                "x-custom-header-a: " .. custom_header_a,
                "x-custom-header-b: " .. custom_header_b
            }
            signing_string = core.table.concat(signing_string, "\n") .. "\n"
            core.log.info("signing_string:", signing_string)

            local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)

            core.log.info("signature:", ngx_encode_base64(signature))
            local headers = {}
            headers["Date"] = gmt
            headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target date digest x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
            headers["x-custom-header-a"] = custom_header_a
            headers["x-custom-header-b"] = custom_header_b

            local code, body = t.test('/hello',
                ngx.HTTP_POST,
                body,
                nil,
                headers
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 401
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid digest
--- response_body eval
qr/\{"message":"client request can't be validated"\}/



=== TEST 4: verify body digest: not ok
--- config
    location /t {
        content_by_lua_block {
            local ngx_time = ngx.time
            local ngx_http_time = ngx.http_time
            local core = require("apisix.core")
            local t = require("lib.test_admin")
            local hmac = require("resty.hmac")
            local ngx_encode_base64 = ngx.encode_base64

            local secret_key = "my-secret-key"
            local timestamp = ngx_time()
            local gmt = ngx_http_time(timestamp)
            local key_id = "my-access-key"
            local custom_header_a = "asld$%dfasf"
            local custom_header_b = "23879fmsldfk"
            local body = "{\"name\": \"world\"}"

            local signing_string = {
                key_id,
                "POST /hello",
                "date: " .. gmt,
                "digest: hello",
                "x-custom-header-a: " .. custom_header_a,
                "x-custom-header-b: " .. custom_header_b
            }
            signing_string = core.table.concat(signing_string, "\n") .. "\n"
            core.log.info("signing_string:", signing_string)

            local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)

            core.log.info("signature:", ngx_encode_base64(signature))
            local headers = {}
            headers["Date"] = gmt
            headers["Authorization"] ="Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target date digest x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
            headers["Digest"] = "hello"
            headers["x-custom-header-a"] = custom_header_a
            headers["x-custom-header-b"] = custom_header_b

            local code, body = t.test('/hello',
                ngx.HTTP_POST,
                body,
                nil,
                headers
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 401
--- grep_error_log eval
qr/client request can't be validated: [^,]+/
--- grep_error_log_out
client request can't be validated: Invalid digest
--- response_body eval
qr/\{"message":"client request can't be validated"\}/



=== TEST 5: verify body digest: ok
--- config
    location /t {
        content_by_lua_block {
            local ngx_time = ngx.time
            local ngx_http_time = ngx.http_time
            local core = require("apisix.core")
            local t = require("lib.test_admin")
            local hmac = require("resty.hmac")
            local ngx_encode_base64 = ngx.encode_base64

            local secret_key = "my-secret-key"
            local timestamp = ngx_time()
            local gmt = ngx_http_time(timestamp)
            local key_id = "my-access-key"
            local custom_header_a = "asld$%dfasf"
            local custom_header_b = "23879fmsldfk"
            local body = "{\"name\": \"world\"}"

            local resty_sha256 = require("resty.sha256")
            local hash = resty_sha256:new()
            hash:update(body)
            local body_digest = ngx_encode_base64(hash:final())

            local signing_string = {
                key_id,
                "POST /hello",
                "date: " .. gmt,
                "digest: SHA-256=" .. body_digest,
                "x-custom-header-a: " .. custom_header_a,
                "x-custom-header-b: " .. custom_header_b
            }
            signing_string = core.table.concat(signing_string, "\n") .. "\n"
            core.log.info("signing_string:", signing_string)

            local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)
            local ngx_encode_base64 = ngx.encode_base64

            core.log.info("signature:", ngx_encode_base64(signature))
            local headers = {}
            headers["Date"] = gmt
            headers["Digest"] = "SHA-256=" .. body_digest
            headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target date digest x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
            headers["x-custom-header-a"] = custom_header_a
            headers["x-custom-header-b"] = custom_header_b

            local code, body = t.test('/hello',
                ngx.HTTP_POST,
                body,
                nil,
                headers
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 6: enable hmac auth with a small max_req_body_size
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "hmac-auth": {
                            "validate_request_body": true,
                            "signed_headers": ["date", "digest"],
                            "max_req_body_size": 10
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 7: request body larger than max_req_body_size is rejected with 413
--- config
    location /t {
        content_by_lua_block {
            local ngx_time = ngx.time
            local ngx_http_time = ngx.http_time
            local core = require("apisix.core")
            local t = require("lib.test_admin")
            local hmac = require("resty.hmac")
            local ngx_encode_base64 = ngx.encode_base64

            local secret_key = "my-secret-key"
            local timestamp = ngx_time()
            local gmt = ngx_http_time(timestamp)
            local key_id = "my-access-key"
            local custom_header_a = "asld$%dfasf"
            local custom_header_b = "23879fmsldfk"
            local body = "{\"name\": \"this body is well over ten bytes\"}"

            local resty_sha256 = require("resty.sha256")
            local hash = resty_sha256:new()
            hash:update(body)
            local body_digest = ngx_encode_base64(hash:final())

            local signing_string = {
                key_id,
                "POST /hello",
                "date: " .. gmt,
                "digest: SHA-256=" .. body_digest,
                "x-custom-header-a: " .. custom_header_a,
                "x-custom-header-b: " .. custom_header_b
            }
            signing_string = core.table.concat(signing_string, "\n") .. "\n"

            local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)

            local headers = {}
            headers["Date"] = gmt
            headers["Digest"] = "SHA-256=" .. body_digest
            headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target date digest x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
            headers["x-custom-header-a"] = custom_header_a
            headers["x-custom-header-b"] = custom_header_b

            local code, body = t.test('/hello',
                ngx.HTTP_POST,
                body,
                nil,
                headers
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 413
--- error_log
failed to read request body



=== TEST 8: request body within max_req_body_size is accepted
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "hmac-auth": {
                            "validate_request_body": true,
                            "signed_headers": ["date", "digest"],
                            "max_req_body_size": 1024
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            local ngx_time = ngx.time
            local ngx_http_time = ngx.http_time
            local core = require("apisix.core")
            local at = require("lib.test_admin")
            local hmac = require("resty.hmac")
            local ngx_encode_base64 = ngx.encode_base64

            local secret_key = "my-secret-key"
            local timestamp = ngx_time()
            local gmt = ngx_http_time(timestamp)
            local key_id = "my-access-key"
            local custom_header_a = "asld$%dfasf"
            local custom_header_b = "23879fmsldfk"
            local req_body = "{\"name\": \"world\"}"

            local resty_sha256 = require("resty.sha256")
            local hash = resty_sha256:new()
            hash:update(req_body)
            local body_digest = ngx_encode_base64(hash:final())

            local signing_string = {
                key_id,
                "POST /hello",
                "date: " .. gmt,
                "digest: SHA-256=" .. body_digest,
                "x-custom-header-a: " .. custom_header_a,
                "x-custom-header-b: " .. custom_header_b
            }
            signing_string = core.table.concat(signing_string, "\n") .. "\n"

            local signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(signing_string)

            local headers = {}
            headers["Date"] = gmt
            headers["Digest"] = "SHA-256=" .. body_digest
            headers["Authorization"] = "Signature keyId=\"" .. key_id .. "\",algorithm=\"hmac-sha256\"" .. ",headers=\"@request-target date digest x-custom-header-a x-custom-header-b\",signature=\"" .. ngx_encode_base64(signature) .. "\""
            headers["x-custom-header-a"] = custom_header_a
            headers["x-custom-header-b"] = custom_header_b

            local code, body = at.test('/hello',
                ngx.HTTP_POST,
                req_body,
                nil,
                headers
            )

            ngx.status = code
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 9: reject body validation without signed digest on Admin API writes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/invalid-hmac', ngx.HTTP_PUT, [[{
                "plugins": {
                    "hmac-auth": {
                        "validate_request_body": true
                    }
                },
                "upstream": {
                    "nodes": {"127.0.0.1:1980": 1},
                    "type": "roundrobin"
                },
                "uri": "/invalid-hmac"
            }]])
            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body_like eval
qr/validate_request_body requires 'digest' in signed_headers/



=== TEST 10: legacy unsigned digest remains accepted with a warning
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")
            local hmac = require("resty.hmac")
            local resty_sha256 = require("resty.sha256")

            assert(core.etcd.set("/routes/1", {
                id = "1",
                uri = "/hello",
                plugins = {
                    ["hmac-auth"] = {validate_request_body = true}
                },
                upstream = {
                    nodes = {["127.0.0.1:1980"] = 1},
                    type = "roundrobin"
                }
            }))
            ngx.sleep(1)

            local body = "{\"name\":\"legacy\"}"
            local hash = resty_sha256:new()
            hash:update(body)
            local digest = "SHA-256=" .. ngx.encode_base64(hash:final())
            local date = ngx.http_time(ngx.time())
            local signing_string = "my-access-key\nPOST /hello\ndate: " .. date .. "\n"
            local signature = hmac:new("my-secret-key", hmac.ALGOS.SHA256):final(signing_string)
            local authorization = "Signature keyId=\"my-access-key\",algorithm=\"hmac-sha256\""
                .. ",headers=\"@request-target date\",signature=\""
                .. ngx.encode_base64(signature) .. "\""

            local code, response = t.test('/hello', ngx.HTTP_POST, body, nil, {
                Date = date,
                Digest = digest,
                Authorization = authorization,
            })
            ngx.status = code
            ngx.say(response)
        }
    }
--- response_body
passed
--- error_log
hmac-auth accepted a request whose Digest header was not signed



=== TEST 11: reject unsigned digest nested in multi-auth
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/multi-invalid', ngx.HTTP_PUT, [[{
                "plugins": {
                    "multi-auth": {
                        "auth_plugins": [
                            {"key-auth": {}},
                            {"hmac-auth": {"validate_request_body": true}}
                        ]
                    }
                },
                "upstream": {
                    "nodes": {"127.0.0.1:1980": 1},
                    "type": "roundrobin"
                },
                "uri": "/multi-invalid"
            }]])
            ngx.status = code
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body_like eval
qr/validate_request_body requires 'digest' in signed_headers/



=== TEST 12: accept signed digest nested in multi-auth
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")
            local hmac = require("resty.hmac")
            local resty_sha256 = require("resty.sha256")

            local code, body = t.test('/apisix/admin/routes/multi-valid', ngx.HTTP_PUT, [[{
                "plugins": {
                    "multi-auth": {
                        "auth_plugins": [
                            {"key-auth": {}},
                            {"hmac-auth": {
                                "validate_request_body": true,
                                "signed_headers": ["date", "digest"]
                            }}
                        ]
                    }
                },
                "upstream": {
                    "nodes": {"127.0.0.1:1980": 1},
                    "type": "roundrobin"
                },
                "uri": "/hello"
            }]])
            assert(code < 300, body)
            ngx.sleep(1)

            local body = "{\"name\":\"multi\"}"
            local hash = resty_sha256:new()
            hash:update(body)
            local digest = "SHA-256=" .. ngx.encode_base64(hash:final())
            local date = ngx.http_time(ngx.time())
            local signing_string = "my-access-key\nPOST /hello\ndate: " .. date
                .. "\ndigest: " .. digest .. "\n"
            local signature = hmac:new("my-secret-key", hmac.ALGOS.SHA256):final(signing_string)
            local authorization = "Signature keyId=\"my-access-key\",algorithm=\"hmac-sha256\""
                .. ",headers=\"@request-target date digest\",signature=\""
                .. ngx.encode_base64(signature) .. "\""

            local code, response = t.test('/hello', ngx.HTTP_POST, body, nil, {
                Date = date,
                Digest = digest,
                Authorization = authorization,
            })
            ngx.status = code
            ngx.say(response)
        }
    }
--- response_body
passed



=== TEST 13: signed header names are case-insensitive
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")
            local hmac = require("resty.hmac")
            local resty_sha256 = require("resty.sha256")

            local code, body = t.test('/apisix/admin/routes/mixed-case', ngx.HTTP_PUT, [[{
                "plugins": {
                    "hmac-auth": {
                        "validate_request_body": true,
                        "signed_headers": ["date", "DiGeSt"]
                    }
                },
                "upstream": {
                    "nodes": {"127.0.0.1:1980": 1},
                    "type": "roundrobin"
                },
                "uri": "/hello"
            }]])
            assert(code < 300, body)
            ngx.sleep(1)

            local body = "{\"name\":\"case\"}"
            local hash = resty_sha256:new()
            hash:update(body)
            local digest = "SHA-256=" .. ngx.encode_base64(hash:final())
            local date = ngx.http_time(ngx.time())
            local signing_string = "my-access-key\nPOST /hello\ndate: " .. date
                .. "\ndigest: " .. digest .. "\n"
            local signature = hmac:new("my-secret-key", hmac.ALGOS.SHA256):final(signing_string)
            local authorization = "Signature keyId=\"my-access-key\",algorithm=\"hmac-sha256\""
                .. ",headers=\"@request-target date digest\",signature=\""
                .. ngx.encode_base64(signature) .. "\""

            local code, response = t.test('/hello', ngx.HTTP_POST, body, nil, {
                Date = date,
                Digest = digest,
                Authorization = authorization,
            })
            ngx.status = code
            ngx.say(response)
        }
    }
--- response_body
passed



=== TEST 14: shared service emits one compatibility warning
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")
            local hmac = require("resty.hmac")
            local resty_sha256 = require("resty.sha256")

            assert(core.etcd.delete("/routes/1"))
            assert(core.etcd.delete("/routes/multi-valid"))
            assert(core.etcd.delete("/routes/mixed-case"))
            assert(core.etcd.set("/services/shared-hmac", {
                id = "shared-hmac",
                plugins = {
                    ["hmac-auth"] = {validate_request_body = true}
                },
                upstream = {
                    nodes = {["127.0.0.1:1980"] = 1},
                    type = "roundrobin"
                }
            }))
            assert(core.etcd.set("/routes/shared-a", {
                id = "shared-a",
                uri = "/hello",
                service_id = "shared-hmac"
            }))
            assert(core.etcd.set("/routes/shared-b", {
                id = "shared-b",
                uri = "/hello1",
                service_id = "shared-hmac"
            }))
            ngx.sleep(1)

            local body = "{\"name\":\"shared\"}"
            local hash = resty_sha256:new()
            hash:update(body)
            local digest = "SHA-256=" .. ngx.encode_base64(hash:final())
            local date = ngx.http_time(ngx.time())

            local function request(path)
                local signing_string = "my-access-key\nPOST " .. path
                    .. "\ndate: " .. date .. "\n"
                local signature = hmac:new("my-secret-key", hmac.ALGOS.SHA256):final(signing_string)
                local authorization = "Signature keyId=\"my-access-key\",algorithm=\"hmac-sha256\""
                    .. ",headers=\"@request-target date\",signature=\""
                    .. ngx.encode_base64(signature) .. "\""
                local code, response = t.test(path, ngx.HTTP_POST, body, nil, {
                    Date = date,
                    Digest = digest,
                    Authorization = authorization,
                })
                assert(code == 200, response)
                return response
            end

            request("/hello")
            request("/hello1")
            ngx.say("passed")
        }
    }
--- response_body
passed
--- grep_error_log eval
qr/hmac-auth accepted a request whose Digest header was not signed/
--- grep_error_log_out
hmac-auth accepted a request whose Digest header was not signed
