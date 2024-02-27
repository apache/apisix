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
log_level('info');
worker_connections(256);
no_root_location();
no_shuffle();
run_tests();

__DATA__

=== TEST 1:  create ssl for test.com
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin")

            local ssl_cert = t.read_file("t/certs/apisix.crt")
            local ssl_key =  t.read_file("t/certs/apisix.key")
            local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                core.json.encode(data),
                [[{
                    "value": {
                        "sni": "test.com"
                    },
                    "key": "/apisix/ssls/1"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 2: query with variables
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/graphql",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:8888": 1
                        }
                    },
                    "plugins": {
                        "degraphql": {
                            "query": "query($name: String!) {\n  persons(filter: { name: $name }) {\n    id\n    name\n    blog\n    githubAccount\n    talks {\n      id\n      title\n    }\n  }\n}",
                            "variables": [
                                "name"
                            ]
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 3: hit
--- exec
curl -k -v -H "Host: test.com" \
    -H "Content-Type: application/json" \
    -X POST -d '{"name": "Josh","githubAccount":"npalm"}' \
    --http3-only --resolve "test.com:1994:127.0.0.1" https://test.com:1994/graphql 2>&1 | cat
--- response_body eval
qr/\{"data":\{"persons":\[\{"id":"8","name":"Josh","blog":"","githubAccount":"joshlong","talks":\[\]\}\]\}\}/
