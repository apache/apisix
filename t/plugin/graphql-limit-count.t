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
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $extra_yaml_config = $block->extra_yaml_config // <<_EOC_;
plugins:
    - graphql-limit-count
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    my $extra_init_worker_by_lua = $block->extra_init_worker_by_lua // "";
    $extra_init_worker_by_lua .= <<_EOC_;
        require("lib.test_redis").flush_all()
_EOC_

    $block->set_value("extra_init_worker_by_lua", $extra_init_worker_by_lua);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests;

__DATA__

=== TEST 1: set route: local policy with count 4
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 4,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
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



=== TEST 2: query with depth equal to 4 exhausts quota and subsequent request is rejected
--- pipelined_requests eval
[
    "POST /hello\n" . '{ "query": "query awesomeGraphqlQuery { foo { bar, baz { boo, bee, baa { bar_id, lol } } } }" }',
    "POST /hello\n" . '{ "query": "query awesomeGraphqlQuery { foo { bar, baz { boo, bee, baa { bar_id, lol } } } }" }',
]
--- more_headers
Content-Type: application/json
--- error_code eval
[200, 503]



=== TEST 3: invalid graphql request: wrong method
--- request
HEAD /hello
--- error_code: 405



=== TEST 4: invalid graphql request: post method without body
--- request
POST /hello
--- error_code: 400
--- error_log
failed to read graphql data, request body has zero size
--- response_body eval
qr/Invalid graphql request: can't get graphql request body/



=== TEST 5: invalid graphql request: wrong content-type
--- request
POST /hello
{
    "query": "query{persons{id}}"
}
--- error_code: 400
--- error_log
invalid graphql request, error content-type
--- response_body eval
qr/invalid graphql request, error content-type/



=== TEST 6: invalid graphql request: malformed json body
--- request
POST /hello
{
    "query": "query{persons{id}}",
}
--- more_headers
Content-Type: application/json
--- error_code: 400
--- error_log
invalid graphql request, Expected object key string but found T_OBJ_END at character 38
--- response_body eval
qr/invalid graphql request, Expected object key string/



=== TEST 7: invalid graphql request: json body missing query field
--- request
POST /hello
{
    "test": "query{persons{id}}"
}
--- more_headers
Content-Type: application/json
--- error_code: 400
--- error_log
invalid graphql request, json body[query] is nil
--- response_body eval
qr/invalid graphql request, json body\[query\] is nil/



=== TEST 8: invalid graphql request: application/graphql with unparsable body
--- request
POST /hello
test {
  persons(filter: { name: "Niek" }) {
    name
    blog
    githubAccount
  }
}
--- more_headers
Content-Type: application/graphql
--- error_code: 400
--- error_log eval
qr/failed to parse graphql/
--- response_body eval
qr/Invalid graphql request: failed to parse graphql query/



=== TEST 9: valid application/graphql content-type with shorthand query
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "graphql-limit-count": {
                            "count": 10,
                            "time_window": 60,
                            "rejected_code": 503,
                            "key": "remote_addr"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
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



=== TEST 10: hit - application/graphql content-type accepted
--- request
POST /hello
{ persons { id name } }
--- more_headers
Content-Type: application/graphql
--- error_code: 200
--- response_headers
X-RateLimit-Remaining: 8



=== TEST 11: invalid graphql request: failed to parse graphql
--- request
POST /hello
{
    "query": "query{persons(filter){id}}"
}
--- more_headers
Content-Type: application/json
--- error_code: 400
--- error_log eval
qr/failed to parse graphql: Syntax error near line 1/
--- response_body eval
qr/Invalid graphql request: failed to parse graphql query/



=== TEST 12: invalid graphql request: empty query
--- request
POST /hello
{
    "query": ""
}
--- more_headers
Content-Type: application/json
--- error_code: 400
--- error_log eval
qr/failed to parse graphql: empty query/
--- response_body eval
qr/Invalid graphql request: empty graphql query/



=== TEST 13: set route: redis policy
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "graphql-limit-count": {
                            "allow_degradation": false,
                            "rejected_code": 503,
                            "redis_timeout": 1000,
                            "key_type": "var",
                            "time_window": 60,
                            "show_limit_quota_header": true,
                            "count": 5,
                            "redis_host": "127.0.0.1",
                            "redis_port": 6379,
                            "redis_database": 0,
                            "policy": "redis",
                            "key": "remote_addr"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
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



=== TEST 14: hit redis policy - query with depth equal to 4
--- request
POST /hello
{
  "query": "query awesomeGraphqlQuery { foo { bar, baz { boo, bee, baa { bar_id, lol } } } }"
}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-RateLimit-Remaining: 1



=== TEST 15: set route: redis-cluster policy
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "graphql-limit-count": {
                            "redis_cluster_nodes": ["127.0.0.1:5000", "127.0.0.1:5001"],
                            "redis_cluster_name": "redis-cluster-1",
                            "redis_cluster_ssl": false,
                            "redis_timeout": 1000,
                            "key_type": "var",
                            "time_window": 60,
                            "show_limit_quota_header": true,
                            "allow_degradation": false,
                            "key": "remote_addr",
                            "rejected_code": 503,
                            "count": 5,
                            "policy": "redis-cluster",
                            "redis_cluster_ssl_verify": false
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
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



=== TEST 16: hit redis-cluster policy - query with depth equal to 4
--- request
POST /hello
{
  "query": "query awesomeGraphqlQuery { foo { bar, baz { boo, bee, baa { bar_id, lol } } } }"
}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
X-RateLimit-Remaining: 1
