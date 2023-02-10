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

=== TEST 1: simulate simple SOAP proxy
--- config
location /demo {
    content_by_lua_block {
        local core = require("apisix.core")
        local body = core.request.get_body()
        local xml2lua = require("xml2lua")
        local xmlhandler = require("xmlhandler.tree")
        local handler = xmlhandler:new()
        local parser = xml2lua.parser(handler)
        parser:parse(body)

        ngx.print(string.format([[
<SOAP-ENV:Envelope
    xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
    <SOAP-ENV:Header/>
    <SOAP-ENV:Body>
        <ns2:getCountryResponse
            xmlns:ns2="http://spring.io/guides/gs-producing-web-service">
            <ns2:country>
                <ns2:name>%s</ns2:name>
                <ns2:population>46704314</ns2:population>
                <ns2:capital>Madrid</ns2:capital>
                <ns2:currency>EUR</ns2:currency>
            </ns2:country>
        </ns2:getCountryResponse>
    </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
        ]], handler.root["soap-env:Envelope"]["soap-env:Body"]["ns0:getCountryRequest"]["ns0:name"]))
    }
}
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            local req_template = ngx.encode_base64[[
<?xml version="1.0"?>
<soap-env:Envelope xmlns:soap-env="http://schemas.xmlsoap.org/soap/envelope/">
 <soap-env:Body>
  <ns0:getCountryRequest xmlns:ns0="http://spring.io/guides/gs-producing-web-service">
   <ns0:name>{{_escape_xml(name)}}</ns0:name>
  </ns0:getCountryRequest>
 </soap-env:Body>
</soap-env:Envelope>
            ]]

            local rsp_template = ngx.encode_base64[[
{% if Envelope.Body.Fault == nil then %}
{
   "status":"{{_ctx.var.status}}",
   "currency":"{{Envelope.Body.getCountryResponse.country.currency}}",
   "population":{{Envelope.Body.getCountryResponse.country.population}},
   "capital":"{{Envelope.Body.getCountryResponse.country.capital}}",
   "name":"{{Envelope.Body.getCountryResponse.country.name}}"
}
{% else %}
{
   "message":{*_escape_json(Envelope.Body.Fault.faultstring[1])*},
   "code":"{{Envelope.Body.Fault.faultcode}}"
   {% if Envelope.Body.Fault.faultactor ~= nil then %}
   , "actor":"{{Envelope.Body.Fault.faultactor}}"
   {% end %}
}
{% end %}
            ]]

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/ws",
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/demo"
                        },
                        "body-transformer": {
                            "request": {
                                "template": "%s"
                            },
                            "response": {
                                "input_format": "xml",
                                "template": "%s"
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:%d": 1
                        }
                    }
                }]], req_template, rsp_template, ngx.var.server_port)
            )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            local core = require("apisix.core")
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ws"
            local body = [[{"name": "Spain"}]]
            local opt = {method = "POST", body = body, headers = {["Content-Type"] = "application/json"}}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 200)
            local data1 = core.json.decode(res.body)
            local data2 = core.json.decode[[{"status":"200","currency":"EUR","population":46704314,"capital":"Madrid","name":"Spain"}]]
            assert(core.json.stably_encode(data1), core.json.stably_encode(data2))
        }
    }



=== TEST 2: test JSON-to-JSON
--- config
    location /demo {
        content_by_lua_block {
            local core = require("apisix.core")
            local body = core.request.get_body()
            local data = core.json.decode(body)
            assert(data.foo == "hello world" and data.bar == 30)
        }
    }
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local req_template = [[{"foo":"{{name .. " world"}}","bar":{{age+10}}}]]

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/foobar",
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/demo"
                        },
                        "body-transformer": {
                            "request": {
                                "template": "%s"
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:%d": 1
                        }
                    }
                }]], req_template:gsub('"', '\\"'), ngx.var.server_port)
            )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            local core = require("apisix.core")
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/foobar"
            local body = [[{"name":"hello","age":20}]]
            local opt = {method = "POST", body = body, headers = {["Content-Type"] = "application/json"}}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 200)
        }
    }



=== TEST 3: specify wrong input_format
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local req_template = [[{"foo":"{{name .. " world"}}","bar":{{age+10}}}]]

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/foobar",
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/demo"
                        },
                        "body-transformer": {
                            "request": {
                                "input_format": "xml",
                                "template": "%s"
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:%d": 1
                        }
                    }
                }]], req_template:gsub('"', '\\"'), ngx.var.server_port)
            )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            local core = require("apisix.core")
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/foobar"
            local body = [[{"name":"hello","age":20}]]
            local opt = {method = "POST", body = body, headers = {["Content-Type"] = "application/json"}}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 400)
        }
    }
--- error_log
Error Parsing XML



=== TEST 4: invalid reference in template
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local req_template = [[{"foo":"{{name() .. " world"}}","bar":{{age+10}}}]]

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/foobar",
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/demo"
                        },
                        "body-transformer": {
                            "request": {
                                "template": "%s"
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:%d": 1
                        }
                    }
                }]], req_template:gsub('"', '\\"'), ngx.var.server_port)
            )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            local core = require("apisix.core")
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/foobar"
            local body = [[{"name":"hello","age":20}]]
            local opt = {method = "POST", body = body, headers = {["Content-Type"] = "application/json"}}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 503)
        }
    }
--- grep_error_log eval
qr/transform\(\): request template rendering:.*/
--- grep_error_log_out eval
qr/attempt to call global 'name' \(a string value\)/



=== TEST 5: generate request body from scratch
--- config
    location /demo {
        content_by_lua_block {
            local core = require("apisix.core")
            local body = core.request.get_body()
            local data = core.json.decode(body)
            assert(data.foo == "hello world")
        }
    }
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local req_template = [[{
                "foo":"{{_ctx.var.arg_name .. " world"}}"
            }]]

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/foobar",
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/demo",
                            "method": "POST"
                        },
                        "body-transformer": {
                            "request": {
                                "template": "%s"
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:%d": 1
                        }
                    }
                }]], req_template:gsub('"', '\\"'), ngx.var.server_port)
            )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            local core = require("apisix.core")
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/foobar?name=hello"
            local opt = {method = "GET"}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 200)
        }
    }



=== TEST 6: html escape in template
--- config
    location /demo {
        content_by_lua_block {
            local core = require("apisix.core")
            local body = core.request.get_body()
            local data = core.json.decode(body)
            if (data == nil) or (data.agent:find("ngx_lua/", 0, true) == nil) then
                return ngx.exit(400)
            end
        }
    }
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            -- html escape would escape '/' to '&#47' in string, which may be unexpected.
            -- 'lua-resty-http/0.16.1 (Lua) ngx_lua/10021'
            -- would be escaped into
            -- 'lua-resty-http&#47;0.16.1 (Lua) ngx_lua&#47;10021'
            local req_template = [[{
                "agent":"{{_ctx.var.http_user_agent}}"
            }]]
            local admin_body = [[{
                "uri": "/foobar",
                "plugins": {
                    "proxy-rewrite": {
                        "uri": "/demo",
                        "method": "POST"
                    },
                    "body-transformer": {
                        "request": {
                            "template": "%s"
                        }
                    }
                },
                "upstream": {
                    "type": "roundrobin",
                    "nodes": {
                        "127.0.0.1:%d": 1
                    }
                }
            }]]

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format(admin_body, req_template:gsub('"', '\\"'), ngx.var.server_port)
            )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            local core = require("apisix.core")
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/foobar?name=hello"
            local opt = {method = "GET"}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 400)

            -- disable html escape, now it's ok
            local req_template = [[{"agent":"{*_ctx.var.http_user_agent*}"}]]
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format(admin_body, req_template:gsub('"', '\\"'), ngx.var.server_port)
            )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            local res = httpc:request_uri(uri, opt)
            assert(res.status == 200)
        }
    }



=== TEST 7: parse body in yaml format
--- config
    location /demo {
        content_by_lua_block {
            local core = require("apisix.core")
            local body = core.request.get_body()
            local data = core.json.decode(body)
            if data == nil or data.foobar ~= "hello world" then
                return ngx.exit(400)
            end
        }
    }
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local req_template = [[
            {%
                local yaml = require("tinyyaml")
                local body = yaml.parse(_body)
            %}
            {"foobar":"{{body.foobar.foo .. " " .. body.foobar.bar}}"}
            ]]
            local admin_body = [[{
                "uri": "/foobar",
                "plugins": {
                    "proxy-rewrite": {
                        "uri": "/demo",
                        "method": "POST"
                    },
                    "body-transformer": {
                        "request": {
                            "template": "%s"
                        }
                    }
                },
                "upstream": {
                    "type": "roundrobin",
                    "nodes": {
                        "127.0.0.1:%d": 1
                    }
                }
            }]]

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format(admin_body, req_template:gsub('"', '\\"'), ngx.var.server_port)
            )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            local core = require("apisix.core")
            local http = require("resty.http")
            local body = [[
foobar:
  foo: hello
  bar: world
            ]]
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/foobar"
            local opt = {method = "POST", body = body}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 200)
        }
    }



=== TEST 8: test _escape_json
--- config
    location /demo {
        content_by_lua_block {
            local core = require("apisix.core")
            local body = core.request.get_body()
            local data = core.json.decode(body)
            if data == nil or data.foobar ~= [[hello "world"]] then
                return ngx.exit(400)
            end
        }
    }
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local req_template = [[{"foobar":{*_escape_json(name)*}}]]
            local admin_body = [[{
                "uri": "/foobar",
                "plugins": {
                    "proxy-rewrite": {
                        "uri": "/demo",
                        "method": "POST"
                    },
                    "body-transformer": {
                        "request": {
                            "input_format": "json",
                            "template": "%s"
                        }
                    }
                },
                "upstream": {
                    "type": "roundrobin",
                    "nodes": {
                        "127.0.0.1:%d": 1
                    }
                }
            }]]

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format(admin_body, req_template:gsub('"', '\\"'), ngx.var.server_port)
            )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            local core = require("apisix.core")
            local http = require("resty.http")
            local body = [[{"name":"hello \"world\""}]]
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/foobar"
            local opt = {method = "POST", body = body}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 200)
        }
    }



=== TEST 9: test _escape_xml
--- config
    location /demo {
        content_by_lua_block {
            local core = require("apisix.core")
            local body = core.request.get_body()
            local xml2lua = require("xml2lua")
            local xmlhandler = require("xmlhandler.tree")
            local handler = xmlhandler:new()
            local parser = xml2lua.parser(handler)
            parser:parse(body)
            assert(handler.root.foobar == "<nil>")
        }
    }
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local req_template = [[<foobar>{*_escape_xml(name)*}</foobar>]]
            local admin_body = [[{
                "uri": "/foobar",
                "plugins": {
                    "proxy-rewrite": {
                        "uri": "/demo",
                        "method": "POST"
                    },
                    "body-transformer": {
                        "request": {
                            "input_format": "json",
                            "template": "%s"
                        }
                    }
                },
                "upstream": {
                    "type": "roundrobin",
                    "nodes": {
                        "127.0.0.1:%d": 1
                    }
                }
            }]]

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format(admin_body, req_template:gsub('"', '\\"'), ngx.var.server_port)
            )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            local core = require("apisix.core")
            local http = require("resty.http")
            local body = [[{"name":"<nil>"}]]
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/foobar"
            local opt = {method = "POST", body = body}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 200)
        }
    }
