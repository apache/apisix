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
log_level('info');
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.xml-json-conversion")
            local conf = {from = "xml", to = "json"}

            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 2: enable xml-json-conversion plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "xml-json-conversion": {
                            "from": "xml",
                            "to": "json"
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]


=== TEST 3: test for unsupported operation
--- request
GET /hello
<people>
 <person>
   <name>Manoel</name>
   <city>Palmas-TO</city>
 </person>
</people>
--- more_headers
Content-Type: text/html
--- error_code: 400
--- response_body
{"message":"Operation not supported"}
--- no_error_log
[error]

=== TEST 4: test for unsupported operation
--- request
GET /hello
<people>
 <person>
   <name>Manoel</name>
   <city>Palmas-TO</city>
 </person>
</people>
--- more_headers
Content-Type: application/json
--- error_code: 400
--- response_body
{"message":"Operation not supported"}
--- no_error_log
[error]


=== TEST 5: verify in argument
--- config
    location /t {
        content_by_lua_block {
            local headers = {}
            headers["Content-Type"] = "text/xml"
            local t = require("lib.test_admin").test
            local code, body = t('/hello',
                ngx.HTTP_GET,
                [[<people>
                     <person>
                       <name>Manoel</name>
                       <city>Palmas-TO</city>
                     </person>
                   </people>]],
               nil,
               headers
            )

            if code > 200 then
                ngx.status = code
                ngx.say(err)
                return
            end

            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]
