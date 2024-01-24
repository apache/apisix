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
            assert(core.json.stably_encode(data1) == core.json.stably_encode(data2))
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



=== TEST 10: cooperation of proxy-cache plugin
--- http_config
lua_shared_dict memory_cache 50m;
--- config
location /demo {
    content_by_lua_block {
        ngx.say([[
    <SOAP-ENV:Envelope
        xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
    <SOAP-ENV:Header/>
        <SOAP-ENV:Body>
            <ns2:CapitalCityResponse
                xmlns:ns2="http://spring.io/guides/gs-producing-web-service">
                <ns2:CapitalCityResult>hello</ns2:CapitalCityResult>
            </ns2:CapitalCityResponse>
        </SOAP-ENV:Body>
    </SOAP-ENV:Envelope>
        ]])
    }
}

    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            local req_template = ngx.encode_base64[[
                <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:web="http://www.oorsprong.org/websamples.countryinfo">
                <soapenv:Header/>
                <soapenv:Body>
                    <web:CapitalCity>
                    <web:sCountryISOCode>{{_escape_xml(country)}}</web:sCountryISOCode>
                    </web:CapitalCity>
                </soapenv:Body>
                </soapenv:Envelope>
            ]]

            local rsp_template = ngx.encode_base64[[
                {"result": {*_escape_json(Envelope.Body.CapitalCityResponse.CapitalCityResult)*}}
                ]]

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/capital",
                    "plugins": {
                        "proxy-rewrite": {
                            "set": {
                                "Accept-Encoding": "identity",
                                "Content-Type": "text/xml"
                            },
                            "uri": "/demo"
                        },
                        "proxy-cache":{
                            "cache_strategy": "memory",
                            "cache_bypass": ["$arg_bypass"],
                            "cache_http_status": [200],
                            "cache_key": ["$uri", "-cache-id"],
                            "cache_method": ["POST"],
                            "hide_cache_headers": true,
                            "no_cache": ["$arg_test"],
                            "cache_zone": "memory_cache"
                        },
                        "body-transformer": {
                            "request": {
                                "input_format": "json",
                                "template": "%s"
                            },
                            "response": {
                                "input_format": "xml",
                                "template": "%s"
                            }
                        },
                        "response-rewrite":{
                            "headers": {
                                "set": {
                                    "Content-Type": "application/json"
                                }
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

            local core = require("apisix.core")
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/capital"
            local body = [[{"country": "foo"}]]
            local opt = {method = "POST", body = body}
            local httpc = http.new()

            local res = httpc:request_uri(uri, opt)
            assert(res.status == 200)
            local data = core.json.decode(res.body)
            assert(data.result == "hello")
            assert(res.headers["Apisix-Cache-Status"] == "MISS")

            local res2 = httpc:request_uri(uri, opt)
            assert(res2.status == 200)
            local data2 = core.json.decode(res2.body)
            assert(data2.result == "hello")
            assert(res2.headers["Apisix-Cache-Status"] == "HIT")
        }
    }



=== TEST 11: return raw body with _body anytime
--- http_config
--- config
    location /demo {
        content_by_lua_block {
            ngx.header.content_type = "application/json"
            ngx.print('{"result": "hello world"}')
        }
    }

    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            local rsp_template = ngx.encode_base64[[
                {"raw_body": {*_escape_json(_body)*}, "result": {*_escape_json(result)*}}
                ]]

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/capital",
                    "plugins": {
                        "proxy-rewrite": {
                            "uri": "/demo"
                        },
                        "body-transformer": {
                            "response": {
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
                }]], rsp_template, ngx.var.server_port)
            )

            local core = require("apisix.core")
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/capital"
            local opt = {method = "GET", headers = {["Content-Type"] = "application/json"}}
            local httpc = http.new()

            local res = httpc:request_uri(uri, opt)
            assert(res.status == 200)
            local data = core.json.decode(res.body)
            assert(data.result == "hello world")
            assert(data.raw_body == '{"result": "hello world"}')
        }
    }



=== TEST 12: empty xml value should be rendered as empty string
--- config
    location /demo {
        content_by_lua_block {
            ngx.print([[
    <SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xrd="http://x-road.eu/xsd/xroad.xsd" xmlns:prod="http://rr.x-road.eu/producer" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:id="http://x-road.eu/xsd/identifiers" xmlns:repr="http://x-road.eu/xsd/representation.xsd" xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/">
      <SOAP-ENV:Body>
        <prod:RR58isikEpiletResponse>
          <request><Isikukood>33333333333</Isikukood></request>
          <response>
            <Isikukood>33333333333</Isikukood>
            <KOVKood></KOVKood>
          </response>
        </prod:RR58isikEpiletResponse>
      </SOAP-ENV:Body>
    </SOAP-ENV:Envelope>
            ]])
        }
    }

    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            local rsp_template = ngx.encode_base64[[
{ "KOVKood":"{{Envelope.Body.RR58isikEpiletResponse.response.KOVKood}}" }
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
                }]], rsp_template, ngx.var.server_port)
            )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            local core = require("apisix.core")
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ws"
            local opt = {method = "GET"}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 200)
            local data1 = core.json.decode(res.body)
            local data2 = core.json.decode[[{"KOVKood":""}]]
            assert(core.json.stably_encode(data1) == core.json.stably_encode(data2))
        }
    }



=== TEST 13: test x-www-form-urlencoded to JSON
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
            local data = {name = "hello", age = 20}
            local body = ngx.encode_args(data)
            local opt = {method = "POST", body = body, headers = {["Content-Type"] = "application/x-www-form-urlencoded"}}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 200)
        }
    }



=== TEST 14: test get request  to JSON
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
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/foobar" .. "?name=hello&age=20"
            local opt = {method = "GET"}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 200)
        }
    }



=== TEST 15: test input is in base64-encoded urlencoded format
--- config
    location /demo {
      content_by_lua_block {
          local core = require("apisix.core")
          local body = core.request.get_body()
          local data = ngx.decode_args(body)
          assert(data.foo == "hello world" and data.bar == "30")
      }
    }
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local req_template = ngx.encode_base64[[foo={{name .. " world"}}&bar={{age+10}}]]

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
                                "template_is_base64": true,
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
            local data = {name = "hello", age = 20}
            local body = ngx.encode_args(data)
            local opt = {method = "POST", body = body, headers = {["Content-Type"] = "application/x-www-form-urlencoded"}}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 200)
        }
    }



=== TEST 16: test for missing Content-Type and skip body parsing
--- config
    location /demo {
        content_by_lua_block {
            local core = require("apisix.core")
            local body = core.request.get_body()
            assert(body == "{\"message\": \"actually json\"}")
        }
    }
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")

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
                                "input_format": "none",
                                "template": "{\"message\": \"{* string.gsub(_body, 'not ', '') *}\"}"
                            }
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:%d": 1
                        }
                    }
                }]], ngx.var.server_port)
            )

            if code >= 300 then
                ngx.status = code
                return
            end
            ngx.sleep(0.5)

            local http = require("resty.http")
            local httpc = http.new()
            local res, err = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/foobar", {
                method = "POST",
                body = "not actually json",
            })
            assert(res.status == 200)
        }
    }
--- no_error_log
no input format to parse
