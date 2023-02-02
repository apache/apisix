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

=== TEST 1: set route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            local req_template = ngx.encode_base64[[
<?xml version="1.0"?>
<soap-env:Envelope xmlns:soap-env="http://schemas.xmlsoap.org/soap/envelope/">
 <soap-env:Body>
  <ns0:getCountryRequest xmlns:ns0="http://spring.io/guides/gs-producing-web-service">
   <ns0:name>{{name:escape_xml()}}</ns0:name>
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
   "message":"{{Envelope.Body.Fault.faultstring[1]:escape_json()}}",
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
            end
            ngx.sleep(1)
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: hit route
--- config
location /demo {
    content_by_lua_block {
        local core = require("apisix.core")
        local body = core.request.get_body()
        local xml2lua = require("xml2lua")
        local xmlhandler = require("xmlhandler.tree")
        local handler = xmlhandler:new()
        local parser = xml2lua.parser(handler)
        --core.log.error(parser:parse(body))
        ngx.print[[
<SOAP-ENV:Envelope
    xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
    <SOAP-ENV:Header/>
    <SOAP-ENV:Body>
        <ns2:getCountryResponse
            xmlns:ns2="http://spring.io/guides/gs-producing-web-service">
            <ns2:country>
                <ns2:name>Spain</ns2:name>
                <ns2:population>46704314</ns2:population>
                <ns2:capital>Madrid</ns2:capital>
                <ns2:currency>EUR</ns2:currency>
            </ns2:country>
        </ns2:getCountryResponse>
    </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
        ]]
    }
}
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local http = require("resty.http")
        local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/ws"
        local body = [[{"name": "Spain"}]]
        local opt = {method = "POST", body = body, headers = {["Content-Type"] = "application/json"}}
        local httpc = http.new()
        local res, err = httpc:request_uri(uri, opt)
        if not res then
            ngx.say(err)
            return
        end
        assert(res.status == 200)
        local data1 = core.json.decode(res.body)
        local data2 = core.json.decode[[{"status":"200","currency":"EUR","population":46704314,"capital":"Madrid","name":"Spain"}]]
        assert(core.json.stably_encode(data1), core.json.stably_encode(data2))
    }
}
