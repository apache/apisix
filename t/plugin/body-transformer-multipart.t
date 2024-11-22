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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: multipart request body to json request body conversion
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/echo",
                    "plugins": {
                        "body-transformer": {
                            "request": {
                                "template": "{\"foo\":\"{{name .. \" world\"}}\",\"bar\":{{age+10}}}"
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/echo"

            local body = ([[
--AaB03x
Content-Disposition: form-data; name="name"

Larry
--AaB03x
Content-Disposition: form-data; name="age"

10
--AaB03x--]])

            local opt = {method = "POST", body = body, headers = {["Content-Type"] = "multipart/related; boundary=AaB03x"}}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)

            ngx.status = res.status
            ngx.say(res.body or res.reason)
        }
    }
--- response_body
{"foo":"Larry world","bar":20}



=== TEST 2: multipart response body to json response body conversion
--- config
    location /demo {
        content_by_lua_block {
            ngx.header["Content-Type"] = "multipart/related; boundary=AaB03x"
            ngx.say([[
--AaB03x
Content-Disposition: form-data; name="name"

Larry
--AaB03x
Content-Disposition: form-data; name="age"

10
--AaB03x--]])
        }
    }
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/demo"
                        },
                        "body-transformer": {
                            "response": {
                                "template": "{\"foo\":\"{{name .. \" world\"}}\",\"bar\":{{age+10}}}"
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1984": 1
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"

            local opt = {method = "GET"}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)

            ngx.status = res.status
            ngx.say(res.body or res.reason)
        }
    }
--- response_body
{"foo":"Larry world","bar":20}



=== TEST 3: multipart parse result accessible to template renderer
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")

            local req_template = ngx.encode_base64[[
                {%
                    local core = require 'apisix.core'
                    local cjson = require 'cjson'
                    
                    if tonumber(context.age) > 18 then
                        context._multipart:set_simple("status", "major")
                    else
                        context._multipart:set_simple("status", "minor")
                    end
                    
                    local body = context._multipart:tostring()
                %}{* body *}
            ]]

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/echo",
                    "plugins": {
                        "body-transformer": {
                            "response": {
                                "template": "%s"
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]], req_template)
            )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            ------------------------#######################-------------------

            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/echo"

            local body_minor = ([[
--AaB03x
Content-Disposition: form-data; name="name"

Larry
--AaB03x
Content-Disposition: form-data; name="age"

10
--AaB03x--]])


            local opt = {method = "POST", body = body_minor, headers = {["Content-Type"] = "multipart/related; boundary=AaB03x"}}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 200)

            ngx.say(res.body)

        }
    }
--- response_body eval
qr/.*Content-Disposition: form-data; name=\"status\"\r\n\r\nminor.*/



=== TEST 4: multipart parse response accessible to template renderer (test with age == 19)
--- config
    location /t {
        content_by_lua_block {

            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/echo"

            local body_major = ([[
--AaB03x
Content-Disposition: form-data; name="name"

Larry
--AaB03x
Content-Disposition: form-data; name="age"

19
--AaB03x--]])


            local opt = {method = "POST", body = body_major, headers = {["Content-Type"] = "multipart/related; boundary=AaB03x"}}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 200)

            ngx.say(res.body)

        }
    }
--- response_body eval
qr/.*Content-Disposition: form-data; name=\"status\"\r\n\r\nmajor.*/
