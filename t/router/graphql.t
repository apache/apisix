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
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests();

__DATA__

=== TEST 1: set route by name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "methods": ["POST"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello",
                        "vars": [["graphql_name", "==", "repo"]]
                }]=]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: route by name
--- request
POST /hello
query repo {
    owner {
        name
    }
}
--- response_body
hello world



=== TEST 3: set route by operation+name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "methods": ["POST"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello",
                        "vars": [
                            ["graphql_operation", "==", "mutation"],
                            ["graphql_name", "==", "repo"]
                        ]
                }]=]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: route by operation+name
--- request
POST /hello
mutation repo($ep: Episode!, $review: ReviewInput!) {
  createReview(episode: $ep, review: $review) {
    stars
    commentary
  }
}
--- response_body
hello world



=== TEST 5: route by operation+name, miss
--- request
POST /hello
query repo {
    owner {
        name
    }
}
--- error_code: 404



=== TEST 6: multiple operations
--- request
POST /hello
mutation repo($ep: Episode!, $review: ReviewInput!) {
  createReview(episode: $ep, review: $review) {
    stars
    commentary
  }
}
query repo {
    owner {
        name
    }
}
--- response_body
hello world
--- error_log
Multiple operations are not supported



=== TEST 7: bad graphql
--- request
POST /hello
AA
--- error_code: 404
--- error_log
failed to parse graphql: Syntax error near line 1 body: AA



=== TEST 8: set anonymous operation name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "methods": ["POST"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello",
                        "vars": [
                            ["graphql_operation", "==", "query"],
                            ["graphql_name", "==", ""]
                        ]
                }]=]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 9: route by anonymous name
--- request
POST /hello
query {
    owner {
        name
    }
}
--- response_body
hello world



=== TEST 10: limit the max size
--- yaml_config
graphql:
    max_size: 5
--- request
POST /hello
query {
    owner {
        name
    }
}
--- error_code: 404
--- error_log
failed to read graphql body



=== TEST 11: set graphql_root_fields
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [=[{
                        "methods": ["POST"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello",
                        "vars": [
                            ["graphql_operation", "==", "query"],
                            ["graphql_root_fields", "has", "owner"]
                        ]
                }]=]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 12: single root field
--- request
POST /hello
query {
    owner {
        name
    }
}
--- response_body
hello world



=== TEST 13: multiple root fields
--- request
POST /hello
query {
    repo {
        stars
    }
    owner {
        name
    }
}
--- response_body
hello world



=== TEST 14: root fields mismatch
--- request
POST /hello
query {
    repo {
        name
    }
}
--- error_code: 404
