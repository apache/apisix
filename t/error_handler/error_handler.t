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

log_level('debug');
repeat_each(1);
no_long_string();
no_root_location();

run_tests;

__DATA__

=== TEST 1: set route with serverless-post-function plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "serverless-post-function": {
                            "functions" : ["return function() if ngx.var.http_x_test_status ~= nil then;ngx.exit(tonumber(ngx.var.http_x_test_status));end;end"]
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/*"
                }]]
                )

            if code >= 300 then
                ngx.sleep(100)
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



=== TEST 2: test apisix with internal error code 500
--- request
GET /hello
--- more_headers
X-Test-Status: 500
--- error_code: 500
--- response_body_like
apisix.apache.org



=== TEST 3: test apisix with internal error code 502
--- request
GET /hello
--- more_headers
X-Test-Status: 502
--- error_code: 502
--- response_body_like
apisix.apache.org



=== TEST 4: test apisix with internal error code 503
--- request
GET /hello
--- more_headers
X-Test-Status: 503
--- error_code: 503
--- response_body_like
apisix.apache.org



=== TEST 5: test apisix with internal error code 504
--- request
GET /hello
--- more_headers
X-Test-Status: 504
--- error_code: 504
--- response_body_like
apisix.apache.org



=== TEST 6: test apisix with internal error code 400
--- request
GET /hello
--- more_headers
X-Test-Status: 400
--- error_code: 400
--- response_body
<html>
<head><title>400 Bad Request</title></head>
<body>
<center><h1>400 Bad Request</h1></center>
<hr><center> <a href="https://apisix.apache.org/">APISIX</a></center>
</body>
</html>



=== TEST 7: test apisix with internal error code 401
--- request
GET /hello
--- more_headers
X-Test-Status: 401
--- error_code: 401
--- response_body
<html>
<head><title>401 Unauthorized</title></head>
<body>
<center><h1>401 Unauthorized</h1></center>
<hr><center> <a href="https://apisix.apache.org/">APISIX</a></center>
</body>
</html>



=== TEST 8: test apisix with internal error code 403
--- request
GET /hello
--- more_headers
X-Test-Status: 403
--- error_code: 403
--- response_body
<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center> <a href="https://apisix.apache.org/">APISIX</a></center>
</body>
</html>



=== TEST 9: test apisix with internal error code 404
--- request
GET /hello
--- more_headers
X-Test-Status: 404
--- error_code: 404
--- response_body
<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center> <a href="https://apisix.apache.org/">APISIX</a></center>
</body>
</html>



=== TEST 10: test apisix with internal error code 405
--- request
GET /hello
--- more_headers
X-Test-Status: 405
--- error_code: 405
--- response_body
<html>
<head><title>405 Not Allowed</title></head>
<body>
<center><h1>405 Not Allowed</h1></center>
<hr><center> <a href="https://apisix.apache.org/">APISIX</a></center>
</body>
</html>



=== TEST 12: test apisix with upstream error code 400
--- request
GET /specific_status
--- more_headers
X-Test-Upstream-Status: 400
--- error_code: 400
--- response_body
upstream status: 400



=== TEST 11: test apisix with upstream error code 500
--- request
GET /specific_status
--- more_headers
X-Test-Upstream-Status: 500
--- error_code: 500
--- response_body
upstream status: 500

