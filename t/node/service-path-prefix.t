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

=== TEST 1: test service path-prefix
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")

            assert(t.test('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[
                    {
                        "plugins": {
                            "proxy-rewrite": {
                                "regex_uri": ["^/foo/(.*)","/$1"]
                            }
                        },
                        "path_prefix": "/foo",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        }
                    }
                ]]
            ))
            ngx.sleep(0.5)

            assert(t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[
                    {
                        "uri": "/*",
                        "service_id": "1"
                    }
                ]]
            ))
            ngx.sleep(0.5)

            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri)
            ngx.status = res.status
            ngx.log(ngx.WARN, require("inspect")(res))
            ngx.print(res.body)
        }
    }
--- request
GET /t
--- response_body
hello world
