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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    my $http_config = $block->http_config // <<_EOC_;
    server {
        listen 12001;

        location /http-logger/test {
            content_by_lua_block {
                ngx.say("test-http-logger-response")
            }
        }

        location /http-logger/Authorization {
            content_by_lua_block {
                ngx.log(ngx.WARN, "received Authorization header: [", ngx.var.http_authorization, "]")
                ngx.say("OK")
            }
        }

        location /http-logger/center {
            content_by_lua_block {
                local function str_split(str, reps)
                    local str_list = {}
                    string.gsub(str, '[^' .. reps .. ']+', function(w)
                        table.insert(str_list, w)
                    end)
                    return str_list
                end

                local args = ngx.req.get_uri_args()
                local query = args.query or nil
                ngx.req.read_body()
                local body = ngx.req.get_body_data()

                if query then
                    if type(query) == "string" then
                        query = {query}
                    end

                    local data, err = require("cjson").decode(body)
                    if err then
                        ngx.log(ngx.WARN, "logs:", body)
                    end

                    for i = 1, #query do
                        local fields = str_split(query[i], ".")
                        local val
                        for j = 1, #fields do
                            local key = fields[j]
                            if j == 1 then
                                val = data[key]
                            else
                                val = val[key]
                            end
                        end
                        ngx.log(ngx.WARN ,query[i], ":", val)
                    end
                else
                    ngx.log(ngx.WARN, "logs:", body)
                end
            }
        }

        location / {
            content_by_lua_block {
                ngx.log(ngx.WARN, "test http logger for root path")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);

    my $extra_init_by_lua = <<_EOC_;
    local bpm = require("apisix.utils.batch-processor-manager")
    bpm.set_check_stale_interval(1)
_EOC_

    $block->set_value("extra_init_by_lua", $extra_init_by_lua);
});

run_tests;

__DATA__

=== TEST 1: check stale batch processor
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "http-logger": {
                                "uri": "http://127.0.0.1:1982/hello",
                                "batch_max_size": 1
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: don't remove current processor
--- request
GET /opentracing
--- error_log
Batch Processor[http logger] successfully processed the entries
--- no_error_log
removing batch processor stale object
--- wait: 0.5



=== TEST 3: remove stale processor
--- request
GET /opentracing
--- error_log
Batch Processor[http logger] successfully processed the entries
removing batch processor stale object
--- wait: 1.5



=== TEST 4: don't remove batch processor which is in used
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "http-logger": {
                                "uri": "http://127.0.0.1:1982/hello",
                                "batch_max_size": 2
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 5: don't remove
--- request
GET /opentracing
--- no_error_log
removing batch processor stale object
--- wait: 1.5



=== TEST 6: set fetch request body and response body route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["POST"],
                        "plugins": {
                            "http-logger": {
                                "uri": "http://127.0.0.1:12001/http-logger/center?query[]=request.body&query[]=response.body",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2,
                                "include_req_body": true,
                                "include_resp_body": true
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:12001": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/http-logger/test"
                }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 7: test fetch request body and response body route
--- request
POST /http-logger/test
test-http-logger-request
--- response_body
test-http-logger-response
--- error_log
request.body:test-http-logger-request
response.body:test-http-logger-response
--- wait: 1.5



=== TEST 8: test default Authorization header sent to the log server
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["POST"],
                        "plugins": {
                            "http-logger": {
                                "uri": "http://127.0.0.1:12001/http-logger/Authorization",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:12001": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/http-logger/test"
                }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 9: hit
--- request
POST /http-logger/test
test-http-logger-request
--- error_log
received Authorization header: [nil]
--- wait: 1.5



=== TEST 10: add default path
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "http-logger": {
                                "uri": "http://127.0.0.1:12001",
                                "batch_max_size": 1,
                                "max_retry_count": 1,
                                "retry_delay": 2,
                                "buffer_duration": 2,
                                "inactive_timeout": 2
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:12001": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/http-logger/test"
                }]])

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 11: hit
--- request
GET /http-logger/test
--- error_log
test http logger for root path
