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
    $ENV{TEST_NGINX_FORCE_RESTART_ON_TEST} = 0;
}

use t::APISIX 'no_plan';

repeat_each(1);
no_shuffle();
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $http_config = $block->http_config // <<_EOC_;

    # for proxy cache
    lua_shared_dict memory_cache 50m;
_EOC_

    $block->set_value("http_config", $http_config);

    # setup default conf.yaml
    my $extra_yaml_config = $block->extra_yaml_config // <<_EOC_;
plugins:
    - graphql-proxy-cache
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

=== TEST 1: set route
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
                            "cache_ttl": 3
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



=== TEST 2: post method: cache miss
--- request
POST /graphql
{
    "query": "query{persons{id}}"
}
--- more_headers
Content-Type: application/json
--- response_headers
Apisix-Cache-Status: MISS
--- response_body chomp
{"data":{"persons":[{"id":"7"},{"id":"8"},{"id":"9"},{"id":"10"},{"id":"11"},{"id":"12"},{"id":"13"},{"id":"14"},{"id":"15"},{"id":"16"},{"id":"17"},{"id":"18"}]}}



=== TEST 3: post method: cache hit
--- request
POST /graphql
{
    "query": "query{persons{id}}"
}
--- more_headers
Content-Type: application/json
--- response_headers
Apisix-Cache-Status: HIT
--- response_body chomp
{"data":{"persons":[{"id":"7"},{"id":"8"},{"id":"9"},{"id":"10"},{"id":"11"},{"id":"12"},{"id":"13"},{"id":"14"},{"id":"15"},{"id":"16"},{"id":"17"},{"id":"18"}]}}



=== TEST 4: get method: cache miss
--- request
GET /graphql?query=query%7Bpersons%7Bid%7D%7D
--- response_headers
Apisix-Cache-Status: MISS
--- response_body chomp
{"data":{"persons":[{"id":"7"},{"id":"8"},{"id":"9"},{"id":"10"},{"id":"11"},{"id":"12"},{"id":"13"},{"id":"14"},{"id":"15"},{"id":"16"},{"id":"17"},{"id":"18"}]}}



=== TEST 5: get method: cache hit
--- request
GET /graphql?query=query%7Bpersons%7Bid%7D%7D
--- response_headers
Apisix-Cache-Status: HIT
--- response_body chomp
{"data":{"persons":[{"id":"7"},{"id":"8"},{"id":"9"},{"id":"10"},{"id":"11"},{"id":"12"},{"id":"13"},{"id":"14"},{"id":"15"},{"id":"16"},{"id":"17"},{"id":"18"}]}}



=== TEST 6: get with variables: cache miss
--- request
GET /graphql?query=query%20(%24name%3A%20String!)%20%7B%0A%20%20persons(filter%3A%20%7B%20name%3A%20%24name%20%7D)%20%7B%0A%20%20%20%20name%0A%20%20%20%20blog%0A%20%20%20%20githubAccount%0A%20%20%7D%0A%7D%0A&variables=%7B%22name%22%3A%22Niek%22%7D
--- response_headers
Apisix-Cache-Status: MISS
--- response_body chomp
{"data":{"persons":[{"name":"Niek","blog":"https://040code.github.io","githubAccount":"npalm"}]}}



=== TEST 7: get with variables: cache hit
--- request
GET /graphql?query=query%20(%24name%3A%20String!)%20%7B%0A%20%20persons(filter%3A%20%7B%20name%3A%20%24name%20%7D)%20%7B%0A%20%20%20%20name%0A%20%20%20%20blog%0A%20%20%20%20githubAccount%0A%20%20%7D%0A%7D%0A&variables=%7B%22name%22%3A%22Niek%22%7D
--- response_headers
Apisix-Cache-Status: HIT
--- response_body chomp
{"data":{"persons":[{"name":"Niek","blog":"https://040code.github.io","githubAccount":"npalm"}]}}



=== TEST 8: post with variables: cache miss
--- request
POST /graphql
{
    "query": "query($name:String!){persons(filter:{name:$name}){name\nblog\ngithubAccount}}",
    "variables": "{\"name\": \"Niek\"}"
}
--- more_headers
Content-Type: application/json
--- response_headers
Apisix-Cache-Status: MISS
--- response_body chomp
{"data":{"persons":[{"name":"Niek","blog":"https://040code.github.io","githubAccount":"npalm"}]}}



=== TEST 9: post with variables: cache hit
--- request
POST /graphql
{
    "query": "query($name:String!){persons(filter:{name:$name}){name\nblog\ngithubAccount}}",
    "variables": "{\"name\": \"Niek\"}"
}
--- more_headers
Content-Type: application/json
--- response_headers
Apisix-Cache-Status: HIT
--- response_body chomp
{"data":{"persons":[{"name":"Niek","blog":"https://040code.github.io","githubAccount":"npalm"}]}}



=== TEST 10: post by grapgql data: cache miss
--- request
POST /graphql
query {
  persons(filter: { name: "Niek" }) {
    name
    blog
    githubAccount
  }
}
--- more_headers
Content-Type: application/graphql
--- response_headers
Apisix-Cache-Status: MISS
--- response_body chomp
{"data":{"persons":[{"name":"Niek","blog":"https://040code.github.io","githubAccount":"npalm"}]}}



=== TEST 11: post by grapgql data: cache hit
--- request
POST /graphql
query {
  persons(filter: { name: "Niek" }) {
    name
    blog
    githubAccount
  }
}
--- more_headers
Content-Type: application/graphql
--- response_headers
Apisix-Cache-Status: HIT
--- response_body chomp
{"data":{"persons":[{"name":"Niek","blog":"https://040code.github.io","githubAccount":"npalm"}]}}



=== TEST 12: consumer_isolation partitions the cache key by consumer
--- extra_yaml_config
plugins:
    - key-auth
    - proxy-rewrite
    - graphql-proxy-cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local function setup(path, method, body)
                local code, res_body = t(path, method, body)
                if code >= 300 then
                    ngx.status = code
                    ngx.say(res_body)
                    return false
                end
                return true
            end

            if not setup('/apisix/admin/consumers', ngx.HTTP_PUT, [[{
                "username": "gql_alice",
                "plugins": {
                    "key-auth": {
                        "key": "alice-gql-key"
                    }
                }
            }]]) then
                return
            end

            if not setup('/apisix/admin/consumers', ngx.HTTP_PUT, [[{
                "username": "gql_bob",
                "plugins": {
                    "key-auth": {
                        "key": "bob-gql-key"
                    }
                }
            }]]) then
                return
            end

            if not setup('/apisix/admin/routes/gql-isolation', ngx.HTTP_PUT, [[{
                "uri": "/graphql-auth",
                "plugins": {
                    "key-auth": {},
                    "proxy-rewrite": {
                        "uri": "/graphql"
                    },
                    "graphql-proxy-cache": {
                        "cache_zone": "memory_cache",
                        "cache_strategy": "memory",
                        "cache_ttl": 300
                    }
                },
                "upstream": {
                    "nodes": {
                        "127.0.0.1:8888": 1
                    },
                    "type": "roundrobin"
                }
            }]]) then
                return
            end

            -- Wait for consumers + route to propagate to the data plane.
            ngx.sleep(0.5)

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/graphql-auth"
            local body = '{"query":"query{persons{id}}"}'

            local function fetch(apikey)
                local res, err = http.new():request_uri(uri, {
                    method = "POST",
                    body = body,
                    headers = {
                        apikey = apikey,
                        ["Content-Type"] = "application/json",
                    },
                })
                if not res then
                    return nil, err
                end
                return res.status .. "/" .. (res.headers["Apisix-Cache-Status"] or "nil")
            end

            local alice_1 = fetch("alice-gql-key")
            local alice_2 = fetch("alice-gql-key")
            local bob_1   = fetch("bob-gql-key")
            local bob_2   = fetch("bob-gql-key")

            ngx.say("alice_1=", alice_1)
            ngx.say("alice_2=", alice_2)
            ngx.say("bob_1=", bob_1)
            ngx.say("bob_2=", bob_2)
        }
    }
--- request
GET /t
--- response_body
alice_1=200/MISS
alice_2=200/HIT
bob_1=200/MISS
bob_2=200/HIT



=== TEST 13: consumer_isolation=false lets consumers share cached responses
--- extra_yaml_config
plugins:
    - key-auth
    - proxy-rewrite
    - graphql-proxy-cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local code, res_body = t('/apisix/admin/routes/gql-isolation', ngx.HTTP_PUT, [[{
                "uri": "/graphql-auth",
                "plugins": {
                    "key-auth": {},
                    "proxy-rewrite": {
                        "uri": "/graphql"
                    },
                    "graphql-proxy-cache": {
                        "cache_zone": "memory_cache",
                        "cache_strategy": "memory",
                        "cache_ttl": 300,
                        "consumer_isolation": false
                    }
                },
                "upstream": {
                    "nodes": {
                        "127.0.0.1:8888": 1
                    },
                    "type": "roundrobin"
                }
            }]])
            if code >= 300 then
                ngx.status = code
                ngx.say(res_body)
                return
            end

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/graphql-auth"
            local body = '{"query":"query{persons{name}}"}'

            local function fetch(apikey)
                local res, err = http.new():request_uri(uri, {
                    method = "POST",
                    body = body,
                    headers = {
                        apikey = apikey,
                        ["Content-Type"] = "application/json",
                    },
                })
                if not res then
                    return "request failed: " .. (err or "unknown")
                end
                return res.headers["Apisix-Cache-Status"]
            end

            ngx.say("alice_1=", fetch("alice-gql-key"))
            ngx.say("bob_1=",   fetch("bob-gql-key"))
        }
    }
--- request
GET /t
--- response_body
alice_1=MISS
bob_1=HIT



=== TEST 14: cache key includes host/route_id so two routes do not collide
--- extra_yaml_config
plugins:
    - proxy-rewrite
    - graphql-proxy-cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local function put(path, body)
                local code, res_body = t(path, ngx.HTTP_PUT, body)
                if code >= 300 then
                    ngx.status = code
                    ngx.say(res_body)
                    return false
                end
                return true
            end

            local route_tpl = [[{
                "uri": "/PATH",
                "plugins": {
                    "proxy-rewrite": {
                        "uri": "/graphql"
                    },
                    "graphql-proxy-cache": {
                        "cache_zone": "memory_cache",
                        "cache_strategy": "memory",
                        "cache_ttl": 300
                    }
                },
                "upstream": {
                    "nodes": {"127.0.0.1:8888": 1},
                    "type": "roundrobin"
                }
            }]]

            if not put('/apisix/admin/routes/gql-tenant-a',
                       (route_tpl:gsub("PATH", "graphql-tenant-a"))) then return end
            if not put('/apisix/admin/routes/gql-tenant-b',
                       (route_tpl:gsub("PATH", "graphql-tenant-b"))) then return end

            local base = "http://127.0.0.1:" .. ngx.var.server_port
            local body = '{"query":"query{persons{id}}"}'

            local function fetch(path)
                local res, err = http.new():request_uri(base .. path, {
                    method = "POST",
                    body = body,
                    headers = { ["Content-Type"] = "application/json" },
                })
                if not res then
                    return "request failed: " .. (err or "unknown")
                end
                return res.headers["Apisix-Cache-Status"]
            end

            ngx.say("tenant_a_1=", fetch("/graphql-tenant-a"))
            ngx.say("tenant_a_2=", fetch("/graphql-tenant-a"))
            ngx.say("tenant_b_1=", fetch("/graphql-tenant-b"))
            ngx.say("tenant_b_2=", fetch("/graphql-tenant-b"))
        }
    }
--- request
GET /t
--- response_body
tenant_a_1=MISS
tenant_a_2=HIT
tenant_b_1=MISS
tenant_b_2=HIT



=== TEST 15: cache key includes $host so different Host headers do not share cache
--- extra_yaml_config
plugins:
    - proxy-rewrite
    - graphql-proxy-cache
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local code, res_body = t('/apisix/admin/routes/gql-host-iso', ngx.HTTP_PUT, [[{
                "uri": "/graphql-host-iso",
                "plugins": {
                    "proxy-rewrite": {
                        "uri": "/graphql"
                    },
                    "graphql-proxy-cache": {
                        "cache_zone": "memory_cache",
                        "cache_strategy": "memory",
                        "cache_ttl": 300
                    }
                },
                "upstream": {
                    "nodes": {"127.0.0.1:8888": 1},
                    "type": "roundrobin"
                }
            }]])
            if code >= 300 then
                ngx.status = code
                ngx.say(res_body)
                return
            end

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/graphql-host-iso"
            local body = '{"query":"query{persons{id}}"}'

            local function fetch(host)
                local res, err = http.new():request_uri(uri, {
                    method = "POST",
                    body = body,
                    headers = {
                        host = host,
                        ["Content-Type"] = "application/json",
                    },
                })
                if not res then
                    return "request failed: " .. (err or "unknown")
                end
                return res.headers["Apisix-Cache-Status"]
            end

            ngx.say("a_1=", fetch("tenant-a.example"))
            ngx.say("a_2=", fetch("tenant-a.example"))
            ngx.say("b_1=", fetch("tenant-b.example"))
            ngx.say("b_2=", fetch("tenant-b.example"))
        }
    }
--- request
GET /t
--- response_body
a_1=MISS
a_2=HIT
b_1=MISS
b_2=HIT



=== TEST 16: PURGE clears every Vary variant, not just the base key
--- extra_yaml_config
plugins:
    - graphql-proxy-cache
    - public-api
--- http_config
    lua_shared_dict memory_cache 50m;

    server {
        listen 1986;
        server_tokens off;

        location = /graphql-vary-purge {
            content_by_lua_block {
                ngx.header["Vary"] = "X-Variant"
                ngx.say('{"data":{"variant":"', ngx.var.http_x_variant or "none", '"}}')
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local http = require("resty.http")

            local code, res_body = t('/apisix/admin/routes/gql-vary-purge', ngx.HTTP_PUT, [[{
                "uri": "/graphql-vary-purge",
                "plugins": {
                    "graphql-proxy-cache": {
                        "cache_zone": "memory_cache",
                        "cache_strategy": "memory",
                        "cache_ttl": 300
                    }
                },
                "upstream": {
                    "nodes": {"127.0.0.1:1986": 1},
                    "type": "roundrobin"
                }
            }]])
            if code >= 300 then
                ngx.status = code
                ngx.say(res_body)
                return
            end

            local code = t('/apisix/admin/routes/graphql-purge', ngx.HTTP_PUT, [[{
                "uri": "/apisix/plugin/graphql-proxy-cache/*",
                "plugins": {"public-api": {}}
            }]])
            if code >= 300 then
                ngx.status = code
                ngx.say("failed to set purge route")
                return
            end

            local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/graphql-vary-purge"
            local body = '{"query":"query{persons{id}}"}'

            local function fetch(variant)
                local res, err = http.new():request_uri(uri, {
                    method = "POST",
                    body = body,
                    headers = {
                        ["X-Variant"] = variant,
                        ["Content-Type"] = "application/json",
                    },
                })
                if not res then
                    return nil, err
                end
                return res.headers["Apisix-Cache-Status"], res.headers["APISIX-Cache-Key"]
            end

            -- Populate two distinct variants under the same base key.
            local a1 = fetch("a")
            local _, cache_key = fetch("a")
            local b1 = fetch("b")
            local b2 = fetch("b")
            ngx.say("a_miss=", a1)
            ngx.say("b_miss=", b1)
            ngx.say("b_hit=", b2)

            -- PURGE the base key once; the fix must clear both variants.
            local purge_code = t('/apisix/plugin/graphql-proxy-cache/memory/gql-vary-purge/'
                                 .. cache_key, "PURGE")
            ngx.say("purge=", purge_code)

            -- Both variants must MISS again now that the index + variants are gone.
            ngx.say("a_after=", (fetch("a")))
            ngx.say("b_after=", (fetch("b")))
        }
    }
--- request
GET /t
--- response_body
a_miss=MISS
b_miss=MISS
b_hit=HIT
purge=200
a_after=MISS
b_after=MISS
