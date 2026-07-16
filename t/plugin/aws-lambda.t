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

add_block_preprocessor(sub {
    my ($block) = @_;

    my $inside_lua_block = $block->inside_lua_block // "";
    chomp($inside_lua_block);
    my $http_config = $block->http_config // <<_EOC_;

    server {
        listen 8765;

        location /httptrigger {
            content_by_lua_block {
                ngx.req.read_body()
                local msg = "aws lambda invoked"
                ngx.header['Content-Length'] = #msg + 1
                ngx.header['Connection'] = "Keep-Alive"
                ngx.say(msg)
            }
        }

        location /generic {
            content_by_lua_block {
                $inside_lua_block
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: checking iam schema
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.aws-lambda")
            local ok, err = plugin.check_schema({
                function_uri = "https://api.amazonaws.com",
                authorization = {
                    iam = {
                        accesskey = "key1",
                        secretkey = "key2"
                    }
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
done



=== TEST 2: missing fields in iam schema
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.aws-lambda")
            local ok, err = plugin.check_schema({
                function_uri = "https://api.amazonaws.com",
                authorization = {
                    iam = {
                        secretkey = "key2"
                    }
                }
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
property "authorization" validation failed: property "iam" validation failed: property "accesskey" is required



=== TEST 3: create route with aws plugin enabled
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "aws-lambda": {
                                "function_uri": "http://localhost:8765/httptrigger",
                                "authorization": {
                                    "apikey" : "testkey"
                                }
                            }
                        },
                        "uri": "/aws"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: test plugin endpoint
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local core = require("apisix.core")

            local code, _, body, headers = t("/aws", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- headers proxied 2 times -- one by plugin, another by this test case
            core.response.set_header(headers)
            ngx.print(body)
        }
    }
--- response_body
aws lambda invoked
--- response_headers
Content-Length: 19



=== TEST 5: check authz header - apikey
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- passing an apikey
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "aws-lambda": {
                                "function_uri": "http://localhost:8765/generic",
                                "authorization": {
                                    "apikey": "test_key"
                                }
                            }
                        },
                        "uri": "/aws"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)

            local code, _, body = t("/aws", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end
            ngx.print(body)
        }
    }
--- inside_lua_block
local headers = ngx.req.get_headers() or {}
ngx.say("Authz-Header - " .. headers["x-api-key"] or "")

--- response_body
passed
Authz-Header - test_key



=== TEST 6: check authz header - IAM v4 signing
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            -- passing the iam access and secret keys
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "aws-lambda": {
                                "function_uri": "http://localhost:8765/generic",
                                "authorization": {
                                    "iam": {
                                        "accesskey": "KEY1",
                                        "secretkey": "KeySecret"
                                    }
                                }
                            }
                        },
                        "uri": "/aws"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)

            local code, _, body, headers = t("/aws", "GET")
             if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.print(body)
        }
    }
--- inside_lua_block
local headers = ngx.req.get_headers() or {}
ngx.say("Authz-Header - " .. headers["Authorization"] or "")
ngx.say("AMZ-Date - " .. headers["X-Amz-Date"] or "")
ngx.print("invoked")

--- response_body eval
qr/passed
Authz-Header - AWS4-HMAC-SHA256 [ -~]*
AMZ-Date - [\d]+T[\d]+Z
invoked/



=== TEST 7: cleanup route before encryption test
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)
            ngx.say(code)
        }
    }
--- response_body
200



=== TEST 8: iam credentials (accesskey, secretkey) and apikey are encrypted at rest
--- yaml_config
apisix:
    data_encryption:
        enable: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")

            -- create route with both IAM credentials and apikey
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "aws-lambda": {
                                "function_uri": "http://localhost:8765/generic",
                                "authorization": {
                                    "apikey": "test-api-key",
                                    "iam": {
                                        "accesskey": "test-access-key",
                                        "secretkey": "test-secret-key"
                                    }
                                }
                            }
                        },
                        "uri": "/aws"
                }]]
                )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- admin API returns plaintext (framework decrypts on read)
            local code, _, res = t('/apisix/admin/routes/1', ngx.HTTP_GET)
            res = json.decode(res)
            ngx.say(res.value.plugins["aws-lambda"].authorization.iam.secretkey)
            ngx.say(res.value.plugins["aws-lambda"].authorization.iam.accesskey)
            ngx.say(res.value.plugins["aws-lambda"].authorization.apikey)

            -- etcd stores ciphertext: assert value is a non-empty string != plaintext
            local etcd = require("apisix.core.etcd")
            local etcd_res = assert(etcd.get('/routes/1'))
            local plugin_conf = etcd_res.body.node.value.plugins["aws-lambda"]
            local stored_secret = plugin_conf.authorization.iam.secretkey
            local stored_access = plugin_conf.authorization.iam.accesskey
            local stored_apikey = plugin_conf.authorization.apikey

            if type(stored_secret) == "string" and #stored_secret > 0
               and stored_secret ~= "test-secret-key" then
                ngx.say("secretkey encrypted: ok")
            else
                ngx.say("secretkey encrypted: FAIL")
            end
            if type(stored_access) == "string" and #stored_access > 0
               and stored_access ~= "test-access-key" then
                ngx.say("accesskey encrypted: ok")
            else
                ngx.say("accesskey encrypted: FAIL")
            end
            if type(stored_apikey) == "string" and #stored_apikey > 0
               and stored_apikey ~= "test-api-key" then
                ngx.say("apikey encrypted: ok")
            else
                ngx.say("apikey encrypted: FAIL")
            end
        }
    }
--- response_body
test-secret-key
test-access-key
test-api-key
secretkey encrypted: ok
accesskey encrypted: ok
apikey encrypted: ok



=== TEST 9: IAM v4 signing with encoded, multi-value and valueless query params
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "aws-lambda": {
                                "function_uri": "http://localhost:8765/generic",
                                "authorization": {
                                    "iam": {
                                        "accesskey": "KEY1",
                                        "secretkey": "KeySecret"
                                    }
                                }
                            }
                        },
                        "uri": "/aws"
                }]]
            )
            if code >= 300 then
                ngx.status = code
                ngx.say("fail")
                return
            end

            ngx.say(body)

            -- unsorted query string with a percent-encoded key and value,
            -- a value that needs encoding, repeated args and a valueless arg
            local code, _, body = t(
                "/aws?with%20space=a%2Fb%20c&multi=m2&multi=m1&flag&a=*&a-=x",
                "GET")
            if code >= 300 then
                ngx.status = code
            end
            ngx.print(body)
        }
    }
--- inside_lua_block
-- emulate the AWS server side SigV4 validation: rebuild the canonical
-- request from the request actually received and recompute the signature
local hmac = require("resty.hmac")
local resty_sha256 = require("resty.sha256")
local hex_encode = require("resty.string").to_hex

local function hmac256(key, msg)
    return hmac:new(key, hmac.ALGOS.SHA256):final(msg)
end

local function sha256(msg)
    local hash = resty_sha256:new()
    hash:update(msg)
    return hex_encode(hash:final())
end

local function uri_encode(s)
    return (s:gsub("[^A-Za-z0-9%-_.~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

ngx.say("query: ", ngx.var.args)

local headers = ngx.req.get_headers()
local credential, signed_headers, signature = headers["authorization"]:match(
    "^AWS4%-HMAC%-SHA256 Credential=([^,]+), SignedHeaders=([^,]+), Signature=(%x+)$")
local datestamp, region, service = credential:match(
    "/(%d+)/([^/]+)/([^/]+)/aws4_request$")

-- canonical query string: decode every pair received on the wire,
-- then URI-encode and sort the pairs again
local query_pairs = {}
for pair in (ngx.var.args or ""):gmatch("[^&]+") do
    local eq = pair:find("=", 1, true)
    local k, v
    if eq then
        k, v = pair:sub(1, eq - 1), pair:sub(eq + 1)
    else
        k, v = pair, ""
    end
    table.insert(query_pairs,
                 {uri_encode(ngx.unescape_uri(k)), uri_encode(ngx.unescape_uri(v))})
end
table.sort(query_pairs, function(a, b)
    if a[1] ~= b[1] then
        return a[1] < b[1]
    end
    return a[2] < b[2]
end)
local canonical_qs = {}
for i, p in ipairs(query_pairs) do
    canonical_qs[i] = p[1] .. "=" .. p[2]
end

local canonical_headers = {}
local i = 0
for name in signed_headers:gmatch("[^;]+") do
    i = i + 1
    local value = headers[name]:gsub("^%s+", ""):gsub("%s+$", "")
    canonical_headers[i] = name .. ":" .. value .. "\n"
end

ngx.req.read_body()
local canonical_request = ngx.req.get_method() .. "\n"
    .. ngx.var.request_uri:match("^([^?]*)") .. "\n"
    .. table.concat(canonical_qs, "&") .. "\n"
    .. table.concat(canonical_headers) .. "\n"
    .. signed_headers .. "\n"
    .. sha256(ngx.req.get_body_data() or "")

local string_to_sign = "AWS4-HMAC-SHA256\n"
    .. headers["x-amz-date"] .. "\n"
    .. datestamp .. "/" .. region .. "/" .. service .. "/aws4_request\n"
    .. sha256(canonical_request)

local sign_key = hmac256("AWS4" .. "KeySecret", datestamp)
sign_key = hmac256(sign_key, region)
sign_key = hmac256(sign_key, service)
sign_key = hmac256(sign_key, "aws4_request")
local expected = hex_encode(hmac256(sign_key, string_to_sign))

if expected == signature then
    ngx.say("signature: ok")
else
    ngx.say("signature mismatch: got ", signature, ", want ", expected)
end

--- response_body
passed
query: a=%2A&a-=x&flag=&multi=m1&multi=m2&with%20space=a%2Fb%20c
signature: ok
