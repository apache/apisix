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
BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }

    my $http_config = $block->http_config // <<_EOC_;
        server {
            server_name openai;
            listen 16724;

            default_type 'application/json';

            location /v1/chat/completions {
                content_by_lua_block {
                    local json = require("cjson.safe")

                    if ngx.req.get_method() ~= "POST" then
                        ngx.status = 400
                        ngx.say("Unsupported request method: ", ngx.req.get_method())
                    end

                    local header_auth = ngx.req.get_headers()["authorization"]
                    if header_auth ~= "Bearer token" then
                        ngx.status = 401
                        ngx.say("Unauthorized")
                        return
                    end

                    ngx.req.read_body()
                    local body, err = ngx.req.get_body_data()
                    body, err = json.decode(body)

                    if not body.messages or #body.messages < 1 then
                        ngx.status = 400
                        ngx.say([[{ "error": "bad request"}]])
                        return
                    end

                    ngx.status = 200
                    ngx.say(string.format([[
{
  "choices": [
    {
      "finish_reason": "stop",
      "index": 0,
      "message": { "content": "1 + 1 = 2.", "role": "assistant" }
    }
  ],
  "created": 1723780938,
  "id": "chatcmpl-test",
  "model": "%s",
  "object": "chat.completion",
  "system_fingerprint": "fp_test",
  "usage": { "completion_tokens": 5, "prompt_tokens": 8, "total_tokens": 10 }
}
                    ]], body.model or "gpt-4"))
                }
            }
        }
_EOC_

    $block->set_value("http_config", $http_config);
});

run_tests;

__DATA__

=== TEST 1: sanity check - Redis policy schema validation
--- config
    location /t {
        content_by_lua_block {
            local configs = {
                -- valid Redis config
                {
                    limit = 30,
                    time_window = 60,
                    policy = "redis",
                    redis_host = "127.0.0.1",
                },
                -- missing redis_host
                {
                    limit = 30,
                    time_window = 60,
                    policy = "redis",
                },
                -- valid Redis Cluster config
                {
                    limit = 30,
                    time_window = 60,
                    policy = "redis-cluster",
                    redis_cluster_nodes = ["127.0.0.1:6379", "127.0.0.1:6380"],
                    redis_cluster_name = "test-cluster",
                },
                -- missing cluster nodes
                {
                    limit = 30,
                    time_window = 60,
                    policy = "redis-cluster",
                    redis_cluster_name = "test-cluster",
                },
                -- local policy (backward compatibility)
                {
                    limit = 30,
                    time_window = 60,
                },
                -- local policy explicit
                {
                    limit = 30,
                    time_window = 60,
                    policy = "local",
                },
            }
            local plugin = require("apisix.plugins.ai-rate-limiting")
            for i, config in ipairs(configs) do
                local ok, err = plugin.check_schema(config)
                if not ok then
                    ngx.say("config ", i, ": ", err)
                else
                    ngx.say("config ", i, ": passed")
                end
            end
        }
    }
--- response_body
config 1: passed
config 2: then clause did not match
config 3: passed
config 4: then clause did not match
config 5: passed
config 6: passed



=== TEST 2: set route with Redis policy, missing redis_host
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/ai",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-4"
                            },
                            "override": {
                                "endpoint": "http://localhost:16724"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 30,
                            "time_window": 60,
                            "policy": "redis"
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
            ngx.print(body)
        }
    }
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin ai-rate-limiting err: then clause did not match"}



=== TEST 3: set route with Redis policy and redis_host
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/ai",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-4"
                            },
                            "override": {
                                "endpoint": "http://localhost:16724"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 30,
                            "time_window": 60,
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "redis_timeout": 1001
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



=== TEST 4: set route with Redis policy (default port and timeout)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/ai",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-4"
                            },
                            "override": {
                                "endpoint": "http://localhost:16724"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 30,
                            "time_window": 60,
                            "policy": "redis",
                            "redis_host": "127.0.0.1"
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



=== TEST 5: set route with Redis Cluster policy
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/ai",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-4"
                            },
                            "override": {
                                "endpoint": "http://localhost:16724"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 30,
                            "time_window": 60,
                            "policy": "redis-cluster",
                            "redis_cluster_nodes": [
                                "127.0.0.1:6379",
                                "127.0.0.1:6380"
                            ],
                            "redis_cluster_name": "test-cluster"
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



=== TEST 6: set route with instances and Redis policy
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/ai",
                    "plugins": {
                        "ai-proxy-multi": {
                            "fallback_strategy": "instance_health_and_rate_limiting",
                            "instances": [
                                {
                                    "name": "openai-gpt4",
                                    "provider": "openai",
                                    "weight": 1,
                                    "priority": 1,
                                    "auth": {
                                        "header": {
                                            "Authorization": "Bearer token"
                                        }
                                    },
                                    "options": {
                                        "model": "gpt-4"
                                    },
                                    "override": {
                                        "endpoint": "http://localhost:16724"
                                    }
                                },
                                {
                                    "name": "openai-gpt3",
                                    "provider": "openai",
                                    "weight": 1,
                                    "priority": 0,
                                    "auth": {"header": {"Authorization": "Bearer token"}},
                                    "options": {"model": "gpt-3.5-turbo"},
                                    "override": {"endpoint": "http://localhost:16724"}
                                }
                            ],
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "instances": [
                                {
                                    "name": "openai-gpt4",
                                    "limit": 20,
                                    "time_window": 60
                                },
                                {
                                    "name": "openai-gpt3",
                                    "limit": 50,
                                    "time_window": 60
                                }
                            ]
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



=== TEST 7: set route with allow_degradation option
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/ai",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-4"
                            },
                            "override": {
                                "endpoint": "http://localhost:16724"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 30,
                            "time_window": 60,
                            "policy": "redis",
                            "redis_host": "127.0.0.1",
                            "allow_degradation": true
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



=== TEST 8: backward compatibility - local policy without explicit policy field
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/ai",
                    "plugins": {
                        "ai-proxy": {
                            "provider": "openai",
                            "auth": {
                                "header": {
                                    "Authorization": "Bearer token"
                                }
                            },
                            "options": {
                                "model": "gpt-4"
                            },
                            "override": {
                                "endpoint": "http://localhost:16724"
                            },
                            "ssl_verify": false
                        },
                        "ai-rate-limiting": {
                            "limit": 30,
                            "time_window": 60
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
