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
worker_connections(256);
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: query list
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/graphql",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:8888": 1
                        }
                    },
                    "plugins": {
                        "degraphql": {
                            "query": "{\n  persons {\n    id\n    name\n  }\n}\n"
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(0.1)

            local http = require "resty.http"
            local httpc = http.new()
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/graphql"
            local headers = {
                ["Content-Type"] = "application/json"
            }
            local res, err = httpc:request_uri(uri, {headers = headers, method = "POST"})
            if not res then
                ngx.say(err)
                return
            end

            local json = require("toolkit.json")
            ngx.say(json.encode(res.body))
        }
    }
--- response_body
"{\"data\":{\"persons\":[{\"id\":\"7\",\"name\":\"Niek\"},{\"id\":\"8\",\"name\":\"Josh\"},{\"id\":\"9\",\"name\":\"Simon\"},{\"id\":\"10\",\"name\":\"Audun\"},{\"id\":\"11\",\"name\":\"Truls\"},{\"id\":\"12\",\"name\":\"Maria\"},{\"id\":\"13\",\"name\":\"Zahin\"},{\"id\":\"14\",\"name\":\"Roberto\"},{\"id\":\"15\",\"name\":\"Susanne\"},{\"id\":\"16\",\"name\":\"Live JS\"},{\"id\":\"17\",\"name\":\"Dave\"},{\"id\":\"18\",\"name\":\"Matt\"}]}}"



=== TEST 2: query with variables
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/graphql",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:8888": 1
                        }
                    },
                    "plugins": {
                        "degraphql": {
                            "query": "query($name: String!) {\n  persons(filter: { name: $name }) {\n    id\n    name\n    blog\n    githubAccount\n    talks {\n      id\n      title\n    }\n  }\n}",
                            "variables": [
                                "name"
                            ]
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



=== TEST 3: hit
--- request
POST /graphql
{
    "name": "Josh",
    "githubAccount":"npalm"
}
--- more_headers
Content-Type: application/json
--- response_body chomp
{"data":{"persons":[{"id":"8","name":"Josh","blog":"","githubAccount":"joshlong","talks":[]}]}}



=== TEST 4: query with more variables
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/graphql",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:8888": 1
                        }
                    },
                    "plugins": {
                        "degraphql": {
                            "query": "query($name: String!, $githubAccount: String!) {\n  persons(filter: { name: $name, githubAccount: $githubAccount }) {\n    id\n    name\n    blog\n    githubAccount\n    talks {\n      id\n      title\n    }\n  }\n}",
                            "variables": [
                                "name",
                                "githubAccount"
                            ]
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
POST /graphql
{
    "name":"Niek",
    "githubAccount":"npalm"
}
--- more_headers
Content-Type: application/json
--- response_body chomp
{"data":{"persons":[{"id":"7","name":"Niek","blog":"https://040code.github.io","githubAccount":"npalm","talks":[{"id":"19","title":"GraphQL - The Next API Language"},{"id":"20","title":"Immutable Infrastructure"}]}]}}



=== TEST 6: without body
--- request
POST /graphql
--- error_log
missing request body
--- error_code: 400



=== TEST 7: invalid body
--- request
POST /graphql
"AA"
--- more_headers
Content-Type: application/json
--- error_log
invalid request body can't be decoded
--- error_code: 400



=== TEST 8: proxy should ensure the Content-Type is correct
--- request
POST /graphql
{
    "name":"Niek",
    "githubAccount":"npalm"
}
--- response_body chomp
{"data":{"persons":[{"id":"7","name":"Niek","blog":"https://040code.github.io","githubAccount":"npalm","talks":[{"id":"19","title":"GraphQL - The Next API Language"},{"id":"20","title":"Immutable Infrastructure"}]}]}}



=== TEST 9: schema check
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local query1 = "query persons($name: String!) {\n  persons(filter: { name: $name }) {\n    id\n    name\n    blog\n    githubAccount\n    talks {\n      id\n      title\n    }\n  }\n}"
            local query2 = "query githubAccount($name: String!, $githubAccount: String!) {\n  persons(filter: { name: $name, githubAccount: $githubAccount }) {\n    id\n    name\n    blog\n    githubAccount\n    talks {\n      id\n      title\n    }\n  }\n}"
            for _, case in ipairs({
                {input = {
                }},
                {input = {
                    query = "uery {}",
                }},
                {input = {
                    query = "query {}",
                    variables = {},
                }},
                {input = {
                    query = query1 .. query2,
                }},
            }) do
                local code, body = t('/apisix/admin/global_rules/1',
                    ngx.HTTP_PUT,
                    {
                        id = "1",
                        plugins = {
                            ["degraphql"] = case.input
                        }
                    }
                )
                ngx.print(body)
            end
    }
}
--- response_body
{"error_msg":"failed to check the configuration of plugin degraphql err: property \"query\" is required"}
{"error_msg":"failed to check the configuration of plugin degraphql err: failed to parse query: Syntax error near line 1"}
{"error_msg":"failed to check the configuration of plugin degraphql err: property \"variables\" validation failed: expect array to have at least 1 items"}
{"error_msg":"failed to check the configuration of plugin degraphql err: operation_name is required if multiple operations are present in the query"}



=== TEST 10: check operation_name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("apisix.core.json")
            local query1 = "query persons($name: String!) {\n  persons(filter: { name: $name }) {\n    id\n    name\n    blog\n    githubAccount\n    talks {\n      id\n      title\n    }\n  }\n}"
            local query2 = "query githubAccount($name: String!, $githubAccount: String!) {\n  persons(filter: { name: $name, githubAccount: $githubAccount }) {\n    id\n    name\n    blog\n    githubAccount\n    talks {\n      id\n      title\n    }\n  }\n}"
            local query = json.encode(query1 .. query2)

            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/graphql",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:8888": 1
                        }
                    },
                    "plugins": {
                        "degraphql": {
                            "query": ]] .. query .. [[,
                            "operation_name": "persons",
                            "variables": [
                                "name"
                            ]
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



=== TEST 11: hit
--- request
POST /graphql
{
    "name": "Josh",
    "githubAccount":"npalm"
}
--- response_body chomp
{"data":{"persons":[{"id":"8","name":"Josh","blog":"","githubAccount":"joshlong","talks":[]}]}}



=== TEST 12: GET with variables
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/graphql",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:8888": 1
                        }
                    },
                    "plugins": {
                        "degraphql": {
                            "query": "query($name: String!, $githubAccount: String!) {\n  persons(filter: { name: $name, githubAccount: $githubAccount }) {\n    id\n    name\n    blog\n    githubAccount\n    talks {\n      id\n      title\n    }\n  }\n}",
                            "variables": [
                                "name",
                                "githubAccount"
                            ]
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



=== TEST 13: hit
--- request
GET /graphql?name=Niek&githubAccount=npalm
--- response_body chomp
{"data":{"persons":[{"id":"7","name":"Niek","blog":"https://040code.github.io","githubAccount":"npalm","talks":[{"id":"19","title":"GraphQL - The Next API Language"},{"id":"20","title":"Immutable Infrastructure"}]}]}}



=== TEST 14: GET without variables
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/graphql",
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:8888": 1
                        }
                    },
                    "plugins": {
                        "degraphql": {
                            "query": "{\n  persons {\n    id\n    name\n  }\n}\n"
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



=== TEST 15: hit
--- request
GET /graphql
--- response_body chomp
{"data":{"persons":[{"id":"7","name":"Niek"},{"id":"8","name":"Josh"},{"id":"9","name":"Simon"},{"id":"10","name":"Audun"},{"id":"11","name":"Truls"},{"id":"12","name":"Maria"},{"id":"13","name":"Zahin"},{"id":"14","name":"Roberto"},{"id":"15","name":"Susanne"},{"id":"16","name":"Live JS"},{"id":"17","name":"Dave"},{"id":"18","name":"Matt"}]}}
