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



=== TEST 5: multipart field names, quoted boundaries and delimiter prefixes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local http = require("resty.http")

            local code = t.test('/apisix/admin/routes/1', ngx.HTTP_PUT, {
                uri = "/multipart-dependency-regression",
                plugins = {
                    ["proxy-rewrite"] = { uri = "/echo" },
                    ["body-transformer"] = {
                        request = {
                            template = "{*_escape_json(_multipart:get_all_with_arrays())*}"
                        }
                    }
                },
                upstream = {
                    nodes = { ["127.0.0.1:1980"] = 1 }
                }
            })
            assert(code < 300, code)

            local cases = {
                {
                    label = "unquoted field name",
                    boundary = "AaB03x",
                    content_type = "multipart/form-data; boundary=AaB03x",
                    disposition = "form-data; name=login_id",
                    name = "login_id",
                    value = "larry123"
                },
                {
                    label = "quoted parameters",
                    boundary = "AaB;03x",
                    content_type = 'multipart/form-data; BOUNDARY="AaB;03x"; charset=utf-8',
                    disposition = 'form-data; name="user; id"',
                    name = "user; id",
                    value = "larry123"
                },
                {
                    label = "quoted field name whitespace",
                    boundary = "AaB03x",
                    content_type = "multipart/form-data; boundary=AaB03x",
                    disposition = 'form-data; name="user "',
                    name = "user ",
                    value = "larry123"
                },
                {
                    label = "delimiter prefix in content",
                    boundary = "AaB03x",
                    content_type = "multipart/form-data; boundary=AaB03x",
                    disposition = 'form-data; name="note"',
                    name = "note",
                    value = "first\r\n--AaB03x-extra\r\nlast"
                }
            }

            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/multipart-dependency-regression"
            for i, case in ipairs(cases) do
                local body = table.concat({
                    "--" .. case.boundary,
                    "Content-Disposition: " .. case.disposition,
                    "",
                    case.value,
                    "--" .. case.boundary .. "--",
                    ""
                }, "\r\n")
                local res, err
                for attempt = 1, 50 do
                    res, err = httpc:request_uri(uri, {
                        method = "POST",
                        body = body,
                        headers = { ["Content-Type"] = case.content_type }
                    })
                    assert(res, err)
                    if i ~= 1 or res.status ~= 404 or attempt == 50 then
                        break
                    end
                    ngx.sleep(0.1)
                end

                assert(res.status == 200, res.status)
                local data = assert(core.json.decode(res.body))
                local count = 0
                for _ in pairs(data) do
                    count = count + 1
                end
                if count == 1 and data[case.name] == case.value then
                    ngx.say(case.label, ": passed")
                else
                    ngx.say(case.label, ": ", res.body)
                end
            end
        }
    }
--- response_body
unquoted field name: passed
quoted parameters: passed
quoted field name whitespace: passed
delimiter prefix in content: passed
--- no_error_log
[error]
--- timeout: 10
