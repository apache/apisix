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

    # for proxy cache
    lua_shared_dict memory_cache 50m;
    # for proxy cache
    proxy_cache_path /tmp/disk_cache_one levels=1:2 keys_zone=disk_cache_one:50m inactive=1d max_size=1G;
    proxy_cache_path /tmp/disk_cache_two levels=1:2 keys_zone=disk_cache_two:50m inactive=1d max_size=1G;

    # for proxy cache
    map \$upstream_cache_zone \$upstream_cache_zone_info {
        disk_cache_one /tmp/disk_cache_one,1:2;
        disk_cache_two /tmp/disk_cache_two,1:2;
    }
_EOC_

    $block->set_value("http_config", $http_config);

    # setup default conf.yaml
    my $extra_yaml_config = $block->extra_yaml_config // <<_EOC_;
plugins:
    - graphql-proxy-cache
    - public-api
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

=== TEST 1: set route: zone not exists
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "graphql-proxy-cache": {
                            "cache_zone": "fake_zone"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8888": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/graphql"
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
--- error_code: 400
--- response_body eval
qr/"failed to check the configuration of plugin graphql-proxy-cache err: cache_zone fake_zone not found"/



=== TEST 2: set route: wrong cache_strategy
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "graphql-proxy-cache": {
                            "cache_zone": "disk_cache_one",
                            "cache_strategy": "test"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8888": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/graphql"
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
--- error_code: 400
--- response_body eval
qr/"failed to check the configuration of plugin graphql-proxy-cache err: property \\\"cache_strategy\\\" validation failed: matches none of the enum values"/



=== TEST 3: set route: normal
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "graphql-proxy-cache": {
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8888": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/graphql"
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



=== TEST 4: invalid graphql request: wrong method
--- request
HEAD /graphql
--- error_code: 405



=== TEST 5: invalid graphql request: get method without args
--- request
GET /graphql
--- error_code: 400
--- error_log
failed to read graphql data, args has zero size
--- response_body eval
qr/Invalid graphql request: can't get graphql request body/



=== TEST 6: invalid graphql request: get method without args
--- request
GET /graphql?query=query%20(%24name%3A%20String!)%20%7B%0A%20%20persons(filter%3A%20%7B%20name%3A%20%24name%20%7D)%20%7B%0A%20%20%20%20name%0A%20%20%20%20blog%0A%20%20%20%20githubAccount%0A%20%20%7D%0A%7D%0A&variables=%7B%22name%22%3A%22Niek%22%7D
--- yaml_config
graphql:
  max_size: 20
--- error_code: 400
--- error_log
failed to read graphql data, args size 234 is greater than the maximum size 20 allowed
--- response_body eval
qr/Invalid graphql request: can't get graphql request body/



=== TEST 7: invalid graphql request: no query
--- request
GET /graphql?test=test
--- error_code: 400
--- error_log
invalid graphql request, args[query] is nil
--- response_body eval
qr/invalid graphql request, args\[query\] is nil/



=== TEST 8: invalid graphql request: post method without body
--- request
POST /graphql
--- error_code: 400
--- error_log
failed to read graphql data, request body has zero size
--- response_body eval
qr/Invalid graphql request: can't get graphql request body/



=== TEST 9: invalid graphql request: wrong content-type
--- request
POST /graphql
{
    "query": "query{persons{id}}"
}
--- error_code: 400
--- error_log
invalid graphql request, error content-type
--- response_body eval
qr/invalid graphql request, error content-type/



=== TEST 10: invalid graphql request: wrong json
--- request
POST /graphql
{
    "query": "query{persons{id}}",
}
--- more_headers
Content-Type: application/json
--- error_code: 400
--- error_log
invalid graphql request, Expected object key string but found T_OBJ_END at character 38
--- response_body eval
qr/invalid graphql request, Expected/



=== TEST 11: invalid graphql request: no query
--- request
POST /graphql
{
    "test": "query{persons{id}}"
}
--- more_headers
Content-Type: application/json
--- error_code: 400
--- error_log
invalid graphql request, json body[query] is nil
--- response_body eval
qr/invalid graphql request, json body/



=== TEST 12: invalid graphql request: graphql data no query
--- request
POST /graphql
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
qr/failed to parse graphql: Syntax error near line 1/
--- response_body eval
qr/Invalid graphql request: failed to parse graphql query/



=== TEST 13: invalid graphql request: failed to parse graphql
--- request
POST /graphql
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



=== TEST 14: invalid graphql request: empty query
--- request
POST /graphql
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



=== TEST 15: query contains mutation will bypass
--- request
POST /graphql
{
    "query": "query{persons{id}} mutation{addTalk(talk:{title:\"apisix\"}){id}}"
}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- response_headers
Apisix-Cache-Status: BYPASS



=== TEST 16: purge memory cache: normal
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "graphql-proxy-cache": {
                            "cache_zone": "memory_cache",
                            "cache_strategy": "memory",
                            "cache_ttl": 5
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8888": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/graphql"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            local code, body = t('/apisix/admin/routes/graphql-purge',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "public-api": {}
                    },
                    "uri": "/apisix/plugin/graphql-proxy-cache/*"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            local request = function()
                return t('/graphql', ngx.HTTP_POST,
                    [[
                        {
                            "query": "query{persons{id}}"
                        }
                    ]],
                    nil,
                    {["Content-Type"] = "application/json"}
                    )
            end

            local code, _, _, headers = request()
            assert(code == 200, "request to graphql server failed")
            assert(headers["Apisix-Cache-Status"] == "MISS", "request should miss")
            local cache_key = headers["APISIX-Cache-Key"]

            local code, _, _, headers = request()
            assert(code == 200, "request to graphql server failed")
            assert(headers["Apisix-Cache-Status"] == "HIT", "request should hit")


            local code, body = t('/apisix/plugin/graphql-proxy-cache/memory/1/'..cache_key, "PURGE")
            assert(code == 200, "purge failed")

            local code, _, _, headers = request()
            assert(code == 200, "request to graphql server failed")
            assert(headers["Apisix-Cache-Status"] == "MISS", "cache should MISS after purge")

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 17: purge disk cache: normal
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "graphql-proxy-cache": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:8888": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/graphql"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            local code, body = t('/apisix/admin/routes/graphql-purge',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "public-api": {}
                    },
                    "uri": "/apisix/plugin/graphql-proxy-cache/*"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            local request = function()
                return t('/graphql', ngx.HTTP_POST,
                    [[
                        {
                            "query": "query{persons{id}}"
                        }
                    ]],
                    nil,
                    {["Content-Type"] = "application/json"}
                    )
            end

            -- Notice: should rm /tmp/disk_cache*
            local code, _, _, headers = request()
            assert(code == 200, "request to graphql server failed")
            assert(headers["Apisix-Cache-Status"] == "MISS", "request should miss")
            local cache_key = headers["APISIX-Cache-Key"]

            local code, _, _, headers = request()
            assert(code == 200, "request to graphql server failed")
            assert(headers["Apisix-Cache-Status"] == "HIT", "request should hit")


            local code, body = t('/apisix/plugin/graphql-proxy-cache/disk/1/'..cache_key, "PURGE")
            assert(code == 200, "purge failed")

            local code, _, _, headers = request()
            assert(code == 200, "request to graphql server failed")
            assert(headers["Apisix-Cache-Status"] == "MISS", "cache should MISS after purge")

            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 18: purge cache: wrong route_id
--- request
PURGE /apisix/plugin/graphql-proxy-cache/disk/xxx/abc
--- error_code: 404
--- error_log eval
qr/failed to find graph-proxy-cache conf, route_id: /



=== TEST 19: purge cache: wrong cache key
--- request
PURGE /apisix/plugin/graphql-proxy-cache/disk/1/abc
--- error_code: 404
--- error_log eval
qr/failed to purge graphql cache, file not exits: /
