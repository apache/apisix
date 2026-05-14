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

    my $http_config = $block->http_config // <<_EOC_;
    lua_shared_dict plugin-graphql-limit-count 10m;
    lua_shared_dict plugin-graphql-limit-count-reset-header 10m;
_EOC_

    $block->set_value("http_config", $http_config);

    my $extra_yaml_config = $block->extra_yaml_config // <<_EOC_;
plugins:
    - graphql-limit-count
_EOC_

    $block->set_value("extra_yaml_config", $extra_yaml_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests;

__DATA__

=== TEST 1: set route: normal
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



=== TEST 2: hit - query with depth equal to 4
--- request
POST /hello
{
  "query": "query awesomeGraphqlQuery { foo { bar, baz { boo, bee, baa { bar_id, lol } } } }"
}
--- more_headers
Content-Type: application/json
--- error_code eval
200
--- response_headers
X-RateLimit-Remaining: 0



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
qr/Invalid graphql request: cant't get graphql request body/



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
qr/Invalid graphql request: no query/



=== TEST 6: invalid graphql request: wrong json
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
qr/Invalid graphql request: no query/



=== TEST 7: invalid graphql request: no query
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
qr/Invalid graphql request: no query/



=== TEST 8: invalid graphql request: graphql data no query
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
--- error_log
invalid graphql request, can't find 'query' in request body
--- response_body eval
qr/Invalid graphql request: no query/



=== TEST 9: invalid graphql request: failed to parse graphql
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



=== TEST 10: invalid graphql request: empty query
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



=== TEST 11: set route: graphql limit-count with redis policy
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



=== TEST 12: hit redis policy - query with depth equal to 4
--- request
POST /hello
{
  "query": "query awesomeGraphqlQuery { foo { bar, baz { boo, bee, baa { bar_id, lol } } } }"
}
--- more_headers
Content-Type: application/json
--- error_code eval
200
--- response_headers
X-RateLimit-Remaining: 1



=== TEST 13: set route: graphql limit-count with redis-cluster policy
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



=== TEST 14: hit redis-cluster policy - query with depth equal to 4
--- request
POST /hello
{
  "query": "query awesomeGraphqlQuery { foo { bar, baz { boo, bee, baa { bar_id, lol } } } }"
}
--- more_headers
Content-Type: application/json
--- error_code eval
200
--- response_headers
X-RateLimit-Remaining: 1
