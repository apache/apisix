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

no_long_string();
no_shuffle();
no_root_location();

run_tests;

__DATA__

=== TEST 1: sign proxied SOAP requests and leave other requests untouched
--- config
    location /upstream {
        content_by_lua_block {
            local core = require("apisix.core")
            local xml = require("apisix.plugins.signing.xml")
            local signer = require("apisix.plugins.soap-signer.signer")

            local body = core.request.get_body() or ""
            local signatures = 0
            local doc = xml.parse(body)
            if doc then
                signatures = #xml.find_all(
                    assert(xml.root(doc)), signer.namespaces.ds, "Signature")
                xml.free_document(doc)
            end
            local length = tonumber(ngx.var.http_content_length) or 0
            ngx.say("signatures=", signatures, " length_ok=", length == #body)
        }
    }
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local http = require("resty.http")

            local function read(path)
                local file = assert(io.open(path, "rb"))
                local value = file:read("*a")
                file:close()
                return value
            end

            local code = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                core.json.encode({
                    uri = "/soap",
                    plugins = {
                        ["proxy-rewrite"] = {uri = "/upstream"},
                        ["soap-signer"] = {
                            credentials = {
                                certificate = read("t/certs/server.crt"),
                                private_key = read("t/certs/server.key"),
                            },
                        },
                    },
                    upstream = {
                        type = "roundrobin",
                        nodes = {["127.0.0.1:" .. ngx.var.server_port] = 1},
                    },
                })
            )
            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            local function call(method, content_type, body)
                local res = assert(http.new():request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port .. "/soap",
                    {method = method, body = body,
                     headers = {["Content-Type"] = content_type}}))
                if res.status == 200 then
                    ngx.print(res.status, " ", res.body)
                else
                    ngx.say(res.status, " ", core.json.decode(res.body).message)
                end
            end

            call("POST", "text/xml", '<s:Envelope xmlns:s="'
                 .. 'http://schemas.xmlsoap.org/soap/envelope/">'
                 .. '<s:Body><Ping xmlns="urn:test"/></s:Body></s:Envelope>')
            call("GET", "text/xml")
            call("POST", "application/json", "{}")
            call("POST", "text/xml", "<broken")
        }
    }
--- request
GET /t
--- response_body
200 signatures=1 length_ok=true
200 signatures=0 length_ok=true
415 unsupported_media_type
400 invalid_soap
--- error_log
soap-signer rejected request: invalid_soap
