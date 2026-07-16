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
                local yaml = require("lyaml")
                local body = yaml.load(_body)
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
                                "input_format": "plain",
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



=== TEST 17: malformed multipart body is handled gracefully (no 500)
--- config
    location /demo {
        content_by_lua_block {
            ngx.say("should not reach upstream")
        }
    }
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local core = require("apisix.core")
            local req_template = [[{"foo":"{{foo}}"}]]

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
                                "input_format": "multipart",
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

            local http = require("resty.http")
            local httpc = http.new()
            local res = httpc:request_uri("http://127.0.0.1:" .. ngx.var.server_port .. "/foobar", {
                method = "POST",
                body = "this is not a valid multipart body",
                headers = {
                    ["Content-Type"] = "multipart/form-data; boundary=----WrongBoundary",
                },
            })
            -- the worker must not crash on malformed multipart input. Depending
            -- on the multipart parser, a malformed body either decodes to an
            -- empty part set (request proceeds) or fails decoding (400); both are
            -- graceful. The regression we guard against is a 500.
            ngx.say(res.status == 500 and "crashed" or "ok")
        }
    }
--- response_body
ok
--- no_error_log
[error]



=== TEST 18: body fields cannot shadow reserved template helpers (_escape_json etc.)
--- config
    location /demo {
        content_by_lua_block {
            local core = require("apisix.core")
            local body = core.request.get_body()
            local data = core.json.decode(body)
            if data == nil or data.foobar ~= "safe" then
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

            local http = require("resty.http")
            -- the body tries to shadow every reserved helper with a plain string;
            -- before the fix, calling _escape_json(name) hit the string from the
            -- body (raw keys win over __index) and rendering failed with 503.
            local body = [[{
                "name": "safe",
                "_ctx": "evil",
                "_body": "evil",
                "_escape_xml": "evil",
                "_escape_json": "evil",
                "_multipart": "evil"
            }]]
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/foobar"
            local opt = {method = "POST", body = body}
            local httpc = http.new()
            local res = httpc:request_uri(uri, opt)
            assert(res.status == 200, "expected 200, got " .. res.status)
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]



=== TEST 19: all namespaced keys are renamed (many siblings + repeated elements)
--- config
    location /demo {
        content_by_lua_block {
            local fields = {
                "orderId", "customerName", "customerEmail", "shippingAddress",
                "billingAddress", "paymentMethod", "totalAmount", "currencyCode",
                "orderDate", "deliveryDate", "trackingNumber", "carrierName",
                "productCount", "discountCode", "taxAmount", "shippingFee",
                "orderStatus", "lastModified", "createdBy", "approvedBy",
                "departmentCode", "warehouseId", "priorityLevel", "remarks",
            }
            local parts = {}
            for i, f in ipairs(fields) do
                parts[i] = string.format("<ns2:%s>v%d</ns2:%s>", f, i, f)
            end
            ngx.print(string.format(
                [[<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns2="http://example.com/order"><soapenv:Body><ns2:getOrderResponse>%s<ns2:items><ns2:item><ns2:sku>first</ns2:sku></ns2:item><ns2:item><ns2:sku>second</ns2:sku></ns2:item></ns2:items><ns2:tags><ns2:tag>red</ns2:tag><ns2:tag>green</ns2:tag><ns2:tag>blue</ns2:tag></ns2:tags></ns2:getOrderResponse></soapenv:Body></soapenv:Envelope>]],
                table.concat(parts)))
        }
    }

    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            local rsp_template = ngx.encode_base64[[{*_escape_json(Envelope.Body)*}]]

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
            local httpc = http.new()
            local res = httpc:request_uri(uri, {method = "GET"})
            assert(res.status == 200)
            local data = core.json.decode(res.body)
            assert(data and data.getOrderResponse, "Body.getOrderResponse not found: " .. res.body)
            local resp = data.getOrderResponse

            local fields = {
                "orderId", "customerName", "customerEmail", "shippingAddress",
                "billingAddress", "paymentMethod", "totalAmount", "currencyCode",
                "orderDate", "deliveryDate", "trackingNumber", "carrierName",
                "productCount", "discountCode", "taxAmount", "shippingFee",
                "orderStatus", "lastModified", "createdBy", "approvedBy",
                "departmentCode", "warehouseId", "priorityLevel", "remarks",
            }
            for i, f in ipairs(fields) do
                assert(resp[f] == "v" .. i,
                       string.format("field %s not renamed or wrong: %s", f, tostring(resp[f])))
            end

            -- repeated complex elements: array preserved and keys inside
            -- array elements renamed too
            local items = resp.items and resp.items.item
            assert(type(items) == "table" and #items == 2
                   and items[1].sku == "first" and items[2].sku == "second",
                   "repeated complex elements broken: " .. core.json.encode(resp.items))

            -- repeated simple elements: array preserved
            local tags = resp.tags and resp.tags.tag
            assert(type(tags) == "table" and #tags == 3
                   and tags[1] == "red" and tags[2] == "green" and tags[3] == "blue",
                   "repeated simple elements broken: " .. core.json.encode(resp.tags))

            -- no key anywhere may keep its namespace prefix
            local function scan(tbl, path)
                for k, v in pairs(tbl) do
                    if type(k) == "string" then
                        assert(not k:find(":"),
                               "leftover namespaced key: " .. path .. "." .. k)
                    end
                    if type(v) == "table" then
                        scan(v, path .. "." .. tostring(k))
                    end
                end
            end
            scan(data, "Body")

            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 20: key renaming must not depend on table layout (varied key sets)
--- config
    location /demo {
        content_by_lua_block {
            -- echo the request body so each request controls the XML
            -- the response transformer has to parse
            ngx.print(require("apisix.core").request.get_body())
        }
    }

    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            local rsp_template = ngx.encode_base64[[{*_escape_json(Envelope.Body.Resp)*}]]

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
            local httpc = http.new()

            -- LuaJIT randomizes its string hash seed per process, so a
            -- traversal-order bug shows up only for some key sets in any
            -- given process. Sweep many sibling counts and several naming
            -- schemes to cover many table layouts.
            local schemes = {
                function (n, i) return "k" .. i end,
                function (n, i) return "longFieldName" .. i .. "x" .. n end,
                function (n, i) return "f" .. i .. string.rep("z", i % 7) end,
            }
            for n = 4, 64, 2 do
                for si, scheme in ipairs(schemes) do
                    local names, parts = {}, {}
                    for i = 1, n do
                        names[i] = scheme(n, i)
                        parts[i] = string.format("<ns:%s>v%d</ns:%s>",
                                                 names[i], i, names[i])
                    end
                    local xml = string.format(
                        [[<env:Envelope xmlns:env="http://e" xmlns:ns="http://n"><env:Body><ns:Resp>%s</ns:Resp></env:Body></env:Envelope>]],
                        table.concat(parts))
                    local res = httpc:request_uri(uri, {method = "POST", body = xml})
                    assert(res.status == 200)
                    local data = core.json.decode(res.body)
                    assert(data, string.format(
                        "n=%d scheme=%d: transform failed, body: %s", n, si, res.body))
                    for i = 1, n do
                        assert(data[names[i]] == "v" .. i, string.format(
                            "n=%d scheme=%d: key %s lost or not renamed",
                            n, si, names[i]))
                    end
                end
            end

            ngx.say("passed")
        }
    }
--- timeout: 30
--- response_body
passed
