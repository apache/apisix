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

log_level("info");
repeat_each(1);
no_long_string();
no_root_location();


my $resp_file = 't/assets/ai-proxy-response.json';
open(my $fh, '<', $resp_file) or die "Could not open file '$resp_file' $!";
my $resp = do { local $/; <$fh> };
close($fh);

print "Hello, World!\n";
print $resp;


add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $user_yaml_config = <<_EOC_;
plugins:
  - ai-proxy-multi
_EOC_
    $block->set_value("extra_yaml_config", $user_yaml_config);

    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name openai;
            listen 6724;

            default_type 'application/json';

            location /v1/chat/completions {
                content_by_lua_block {
                    local json = require("cjson.safe")

                    if ngx.req.get_method() ~= "POST" then
                        ngx.status = 400
                        ngx.say("Unsupported request method: ", ngx.req.get_method())
                    end
                    ngx.req.read_body()
                    local body, err = ngx.req.get_body_data()
                    body, err = json.decode(body)

                    local header_auth = ngx.req.get_headers()["authorization"]
                    local query_auth = ngx.req.get_uri_args()["apikey"]

                    if header_auth ~= "Bearer token" and query_auth ~= "apikey" then
                        ngx.status = 401
                        ngx.say("Unauthorized")
                        return
                    end

                    if header_auth == "Bearer token" or query_auth == "apikey" then
                        ngx.req.read_body()
                        local body, err = ngx.req.get_body_data()
                        body, err = json.decode(body)

                        if not body.messages or #body.messages < 1 then
                            ngx.status = 400
                            ngx.say([[{ "error": "bad request"}]])
                            return
                        end

                        ngx.status = 200
                        ngx.print("openai")
                        return
                    end


                    ngx.status = 503
                    ngx.say("reached the end of the test suite")
                }
            }

            location /chat/completions {
                content_by_lua_block {
                    local json = require("cjson.safe")

                    if ngx.req.get_method() ~= "POST" then
                        ngx.status = 400
                        ngx.say("Unsupported request method: ", ngx.req.get_method())
                    end
                    ngx.req.read_body()
                    local body, err = ngx.req.get_body_data()
                    body, err = json.decode(body)

                    local header_auth = ngx.req.get_headers()["authorization"]
                    local query_auth = ngx.req.get_uri_args()["apikey"]

                    if header_auth ~= "Bearer token" and query_auth ~= "apikey" then
                        ngx.status = 401
                        ngx.say("Unauthorized")
                        return
                    end

                    if header_auth == "Bearer token" or query_auth == "apikey" then
                        ngx.req.read_body()
                        local body, err = ngx.req.get_body_data()
                        body, err = json.decode(body)

                        if not body.messages or #body.messages < 1 then
                            ngx.status = 400
                            ngx.say([[{ "error": "bad request"}]])
                            return
                        end

                        ngx.status = 200
                        ngx.print("deepseek")
                        return
                    end


                    ngx.status = 503
                    ngx.say("reached the end of the test suite")
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: set route with roundrobin balancer, weight 4 and 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy-multi": {
                            "providers": [
                                {
                                    "name": "openai",
                                    "model": "gpt-4",
                                    "weight": 4,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724"
                                    }
                                },
                                {
                                    "name": "deepseek",
                                    "model": "gpt-4",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724/chat/completions"
                                    }
                                }
                            ],
                            "ssl_verify": false
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "canbeanything.com": 1
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
--- response_body
passed



=== TEST 2: test
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/anything"

            local restab = {}

            local body = [[{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }]]
            for i = 1, 10 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "POST", body = body})
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(restab, res.body)
            end

            table.sort(restab)
            ngx.log(ngx.WARN, "test picked providers: ", table.concat(restab, "."))

        }
    }
--- request
GET /t
--- error_log
deepseek.deepseek.openai.openai.openai.openai.openai.openai.openai.openai



=== TEST 3: set route with chash balancer, weight 4 and 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy-multi": {
                            "balancer": {
                                "algorithm": "chash",
                                "hash_on": "vars",
                                "key": "query_string"
                            },
                            "providers": [
                                {
                                    "name": "openai",
                                    "model": "gpt-4",
                                    "weight": 4,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724"
                                    }
                                },
                                {
                                    "name": "deepseek",
                                    "model": "gpt-4",
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724/chat/completions"
                                    }
                                }
                            ],
                            "ssl_verify": false
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "canbeanything.com": 1
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
--- response_body
passed



=== TEST 4: test
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/anything"

            local restab = {}

            local body = [[{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }]]
            for i = 1, 10 do
                local httpc = http.new()
                local query = {
                    index = i
                }
                local res, err = httpc:request_uri(uri, {method = "POST", body = body, query = query})
                if not res then
                    ngx.say(err)
                    return
                end
                table.insert(restab, res.body)
            end

            local count = {}
            for _, value in ipairs(restab) do
                count[value] = (count[value] or 0) + 1
            end

            for p, num in pairs(count) do
                ngx.log(ngx.WARN, "distribution: ", p, ": ", num)
            end

        }
    }
--- request
GET /t
--- timeout: 10
--- error_log
distribution: deepseek: 2
distribution: openai: 8



=== TEST 5: retry logic with different priorities
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/anything",
                    "plugins": {
                        "ai-proxy-multi": {
                            "providers": [
                                {
                                    "name": "openai",
                                    "model": "gpt-4",
                                    "weight": 1,
                                    "priority": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:9999"
                                    }
                                },
                                {
                                    "name": "deepseek",
                                    "model": "gpt-4",
                                    "priority": 0,
                                    "weight": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "max_tokens": 512,
                                        "temperature": 1.0
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:6724/chat/completions"
                                    }
                                }
                            ],
                            "ssl_verify": false
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "canbeanything.com": 1
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
--- response_body
passed



=== TEST 6: test
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/anything"

            local restab = {}

            local body = [[{ "messages": [ { "role": "system", "content": "You are a mathematician" }, { "role": "user", "content": "What is 1+1?"} ] }]]
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "POST", body = body})
                if not res then
                    ngx.say(err)
                    return
                end
                ngx.say(res.body)

        }
    }
--- request
GET /t
--- response_body
deepseek
--- error_log
failed to send request to LLM: failed to connect to LLM server: connection refused. Retrying...
