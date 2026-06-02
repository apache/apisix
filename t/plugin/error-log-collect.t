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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->extra_yaml_config) {
        my $extra_yaml_config = <<_EOC_;
plugins:
    - error-log-collect
_EOC_
        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }

});

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.error-log-collect")
            local ok, err = plugin.check_schema({
                vars = {
                    {"arg_debug", "==", "true"}
                },
                sample_ratio = 0.5,
                buffer_max_size = 500
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body
done



=== TEST 2: invalid vars
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.error-log-collect")
            local ok, err = plugin.check_schema({
                vars = "invalid"
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body_like
failed to validate the 'vars' expression



=== TEST 3: invalid sample_ratio
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.error-log-collect")
            local ok, err = plugin.check_schema({
                sample_ratio = 2
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- request
GET /t
--- response_body_like
invalid



=== TEST 4: enable plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "error-log-collect": {
                            "sample_ratio": 1
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
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



=== TEST 5: collect error logs
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.say(err)
                return
            end
            ngx.say(res.status)
        }
    }
--- request
GET /t
--- response_body
200
--- error_log eval
qr/\[error-log-collect\]/
--- no_error_log eval
qr/\[error\]/
--- wait: 2



=== TEST 6: collect with vars filter
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "error-log-collect": {
                            "vars": [
                                ["arg_debug", "==", "true"]
                            ],
                            "sample_ratio": 1
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
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



=== TEST 7: verify vars filter works
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()

            -- Request without debug param (should not collect)
            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
            local res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.say(err)
                return
            end
            ngx.say("without debug: ", res.status)

            -- Request with debug param (should collect)
            uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello?debug=true"
            res, err = httpc:request_uri(uri, {method = "GET"})
            if not res then
                ngx.say(err)
                return
            end
            ngx.say("with debug: ", res.status)
        }
    }
--- request
GET /t
--- response_body
without debug: 200
with debug: 200
--- error_log eval
qr/\[error-log-collect\]/
--- no_error_log eval
qr/\[error\]/
--- wait: 2



=== TEST 8: sampling
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "error-log-collect": {
                            "sample_ratio": 0.00001
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
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



=== TEST 9: verify sampling works
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local httpc = http.new()

            -- Send multiple requests (most should not be sampled)
            for i = 1, 10 do
                local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/hello"
                local res, err = httpc:request_uri(uri, {method = "GET"})
                if not res then
                    ngx.say(err)
                    return
                end
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- error_log eval
qr/\[error-log-collect\]/
--- no_error_log eval
qr/\[error\]/
--- wait: 5
