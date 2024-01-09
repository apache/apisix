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

log_level('info');
repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $yaml_config = $block->yaml_config // <<_EOC_;
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

    $block->set_value("yaml_config", $yaml_config);
});

run_tests;

__DATA__

=== TEST 1: json body with request_body
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
    plugins:
        http-logger:
            batch_max_size: 1
            uri: http://127.0.0.1:1980/log
            include_req_body: true
#END
--- request
POST /hello
{"sample_payload":"hello"}
--- error_log
"body":"{\"sample_payload\":\"hello\"}"



=== TEST 2: json body with response_body
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
    plugins:
        http-logger:
            batch_max_size: 1
            uri: http://127.0.0.1:1980/log
            include_resp_body: true
#END
--- request
POST /hello
{"sample_payload":"hello"}
--- error_log
"response":{"body":"hello world\n"



=== TEST 3: json body with response_body and response_body expression
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
    plugins:
        http-logger:
            batch_max_size: 1
            uri: http://127.0.0.1:1980/log
            include_resp_body: true
            include_resp_body_expr:
                - - arg_bar
                  - ==
                  - foo
#END
--- request
POST /hello?bar=foo
{"sample_payload":"hello"}
--- error_log
"response":{"body":"hello world\n"



=== TEST 4: json body with response_body, expr not hit
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
    plugins:
        http-logger:
            batch_max_size: 1
            uri: http://127.0.0.1:1980/log
            include_resp_body: true
            include_resp_body_expr:
                - - arg_bar
                  - ==
                  - foo
#END
--- request
POST /hello?bar=bar
{"sample_payload":"hello"}
--- no_error_log
"response":{"body":"hello world\n"



=== TEST 5: json body with request_body and response_body
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
    plugins:
        http-logger:
            batch_max_size: 1
            uri: http://127.0.0.1:1980/log
            include_req_body: true
            include_resp_body: true
#END
--- request
POST /hello
{"sample_payload":"hello"}
--- error_log eval
qr/(.*"response":\{.*"body":"hello world\\n".*|.*\{\\\"sample_payload\\\":\\\"hello\\\"\}.*){2}/



=== TEST 6: json body without request_body or response_body
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
    plugins:
        http-logger:
            batch_max_size: 1
            uri: http://127.0.0.1:1980/log
#END
--- request
POST /hello
{"sample_payload":"hello"}
--- error_log eval
qr/(.*"response":\{.*"body":"hello world\\n".*|.*\{\\\"sample_payload\\\":\\\"hello\\\"\}.*){0}/



=== TEST 7: json body with request_body and request_body expression
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
    plugins:
        http-logger:
            batch_max_size: 1
            uri: http://127.0.0.1:1980/log
            include_req_body: true
            include_req_body_expr:
                - - arg_bar
                  - ==
                  - foo
#END
--- request
POST /hello?bar=foo
{"test":"hello"}
--- error_log
"request":{"body":"{\"test\":\"hello\"}"



=== TEST 8: json body with request_body, expr not hit
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
    plugins:
        http-logger:
            batch_max_size: 1
            uri: http://127.0.0.1:1980/log
            include_resp_body: true
            include_resp_body_expr:
                - - arg_bar
                  - ==
                  - foo
#END
--- request
POST /hello?bar=bar
{"sample_payload":"hello"}
--- no_error_log
"request":{"body":"{\"test\":\"hello\"}"
