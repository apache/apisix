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
use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $extra_yaml_config = <<_EOC_;
wasm:
    plugins:
        - name: wasm-request-body
          priority: 7997
          file: t/wasm/request-body/main.go.wasm
        - name: wasm-request-body2
          priority: 7996
          file: t/wasm/request-body/main.go.wasm
_EOC_
    $block->set_value("extra_yaml_config", $extra_yaml_config);
});

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "wasm-request-body": {
                            "conf": "{\"processReqBody\":true, \"start\":1, \"size\":3}"
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
--- response_body
passed



=== TEST 2: hit
--- request
POST /hello
hello
--- grep_error_log eval
qr/request get body: \w+/
--- grep_error_log_out
request get body: ell



=== TEST 3: no body
--- request
POST /hello
--- error_log
error status returned by host: not found



=== TEST 4: do not process body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "wasm-request-body": {
                            "conf": "{\"processReqBody\":false, \"start\":1, \"size\":3}"
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
--- response_body
passed



=== TEST 5: hit
--- request
POST /hello
hello
--- grep_error_log eval
qr/request get body: \w+/
--- grep_error_log_out



=== TEST 6: ensure the process body flag is plugin independent
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "wasm-request-body": {
                            "conf": "{\"processReqBody\":true, \"start\":1, \"size\":3}"
                        },
                        "wasm-request-body2": {
                            "conf": "{\"processReqBody\":false, \"start\":2, \"size\":3}"
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
--- response_body
passed



=== TEST 7: hit
--- request
POST /hello
hello
--- grep_error_log eval
qr/request get body: \w+/
--- grep_error_log_out
request get body: ell



=== TEST 8: invalid conf type no set conf
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    },
                    "plugins": {
                        "wasm-request-body": {
                            "setting": {"processReqBody":true, "start":1, "size":3}
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
--- error_code: 400
--- response_body_like eval
qr/property.*conf.*is required/



=== TEST 9: hit
--- request
POST /hello
hello
--- grep_error_log eval
qr/request get body: \w+/
--- grep_error_log_out
request get body: ell
