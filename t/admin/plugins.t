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
log_level("info");

run_tests;

__DATA__

=== TEST 1: get plugins' name
--- request
GET /apisix/admin/plugins/list
--- response_body_like eval
qr/\["limit-req","limit-count","limit-conn","key-auth","basic-auth","prometheus","node-status","jwt-auth","zipkin","ip-restriction","grpc-transcode","serverless-pre-function","serverless-post-function","openid-connect","proxy-rewrite","redirect","response-rewrite","fault-injection","udp-logger","wolf-rbac","proxy-cache","tcp-logger","proxy-mirror","kafka-logger","cors","consumer-restriction","syslog","batch-requests","http-logger","skywalking","echo","authz-keycloak","uri-blocker"\]/
--- no_error_log
[error]



=== TEST 2: wrong path
--- request
GET /apisix/admin/plugins
--- error_code: 400
--- response_body
{"error_msg":"not found plugin name"}
--- no_error_log
[error]



=== TEST 3: get plugin schema
--- request
GET /apisix/admin/plugins/limit-req
--- response_body
{"properties":{"rate":{"minimum":0,"type":"number"},"burst":{"minimum":0,"type":"number"},"key":{"enum":["remote_addr","server_addr","http_x_real_ip","http_x_forwarded_for"],"type":"string"},"rejected_code":{"type":"integer","default":503,"minimum":200}},"required":["rate","burst","key"],"type":"object"}
--- no_error_log
[error]



=== TEST 4: get plugin node-status schema
--- request
GET /apisix/admin/plugins/node-status
--- response_body
{"additionalProperties":false,"type":"object"}
--- no_error_log
[error]



=== TEST 5: get plugin heartbeat schema
--- request
GET /apisix/admin/plugins/heartbeat
--- response_body
{"additionalProperties":false,"type":"object"}
--- no_error_log
[error]
