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
log_level('warn');
no_root_location();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: configure cert with smaller key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local ssl_cert = t.read_file("t/certs/server_1024.crt")
            local ssl_key = t.read_file("t/certs/server_1024.key")

            local data = {
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1,
                    },
                },
                uri = "/hello"
            }
            assert(t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                json.encode(data)
            ))

            local data = {
                cert = ssl_cert,
                key = ssl_key,
                sni = "localhost",
            }
            local code = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            if code >= 300 then
                ngx.status = code
            end
        }
    }
--- request
GET /t



=== TEST 2: curl failed
--- exec
curl -k https://localhost:1994/hello -H "Host: localhost"
--- error_log
failed to set PEM cert: SSL_use_certificate() failed
