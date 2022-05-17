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

run_tests();

__DATA__

=== TEST 1: enable http_to_https
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "host": "foo.com",
                    "plugins": {
                        "redirect": {
                            "http_to_https": true
                        }
                    }
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



=== TEST 2: redirect port using `apisix.ssl.listen_port`
--- yaml_config
apisix:
    ssl:
        enable: true
        listen_port: 9445
--- extra_yaml_config
plugin_attr:
    redirect_https_port: null
--- request
GET /hello
--- more_headers
Host: foo.com
--- error_code: 301
--- response_headers
Location: https://foo.com:9445/hello


=== TEST 3: redirect port using `apisix.ssl.listen`
--- extra_yaml_config
plugin_attr:
    redirect_https_port: null
--- request
GET /hello
--- more_headers
Host: foo.com
--- error_code: 301
--- response_headers
Location: https://foo.com:9443/hello



=== TEST 4: redirect port using `https default port`
--- yaml_config
apisix:
    ssl:
        enable: null
--- extra_yaml_config
plugin_attr:
    redirect_https_port: null
--- request
GET /hello
--- more_headers
Host: foo.com
--- error_code: 301
--- response_headers
Location: https://foo.com/hello
