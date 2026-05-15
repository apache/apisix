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

run_tests;

__DATA__

=== TEST 1: add consumer jack
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "basic-auth": {
                            "username": "jack",
                            "password": "123456"
                        }
                    },
                    "labels": {
                        "org": "apache",
                        "project": "gateway,apisix,web-server"
                    }
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



=== TEST 2: add consumer rose
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "rose",
                    "plugins": {
                        "basic-auth": {
                            "username": "rose",
                            "password": "123456"
                        }
                    },
                    "labels": {
                        "org": "[\"opensource\",\"apache\"]",
                        "project": "[\"tomcat\",\"web-server\",\"http,server\"]"
                    }
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



=== TEST 3: set allow_labels
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "basic-auth": {},
                            "acl": {
                                 "allow_labels": {
                                    "org": ["apache"]
                                 }
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
--- request
GET /t
--- response_body
passed



=== TEST 4: verify unauthorized
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing authorization in request"}



=== TEST 5: verify jack
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazoxMjM0NTY=
--- response_body
hello world



=== TEST 6: verify rose
--- request
GET /hello
--- more_headers
Authorization: Basic cm9zZToxMjM0NTY=
--- response_body
hello world



=== TEST 7: set allow_labels
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "basic-auth": {},
                            "acl": {
                                 "allow_labels": {
                                     "project": ["apisix"]
                                 }
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
--- request
GET /t
--- response_body
passed



=== TEST 8: verify jack
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazoxMjM0NTY=
--- response_body
hello world



=== TEST 9: verify rose
--- request
GET /hello
--- more_headers
Authorization: Basic cm9zZToxMjM0NTY=
--- error_code: 403
--- response_body
{"message":"The consumer is forbidden."}



=== TEST 10: set deny_labels
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "basic-auth": {},
                            "acl": {
                                 "deny_labels": {
                                     "project": ["apisix"]
                                 },
                                 "rejected_msg": "request is forbidden"
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
--- request
GET /t
--- response_body
passed



=== TEST 11: verify jack
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazoxMjM0NTY=
--- error_code: 403
--- response_body
{"message":"request is forbidden"}



=== TEST 12: verify rose
--- request
GET /hello
--- more_headers
Authorization: Basic cm9zZToxMjM0NTY=
--- response_body
hello world



=== TEST 13: set deny_labels with multiple values
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "basic-auth": {},
                            "acl": {
                                 "deny_labels": {
                                     "project": ["apisix", "tomcat"]
                                 }
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
--- request
GET /t
--- response_body
passed



=== TEST 14: verify jack
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazoxMjM0NTY=
--- error_code: 403



=== TEST 15: verify rose
--- request
GET /hello
--- more_headers
Authorization: Basic cm9zZToxMjM0NTY=
--- error_code: 403



=== TEST 16: set allow_labels with comma
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "basic-auth": {},
                            "acl": {
                                 "allow_labels": {
                                    "project": ["http,server"]
                                 }
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
--- request
GET /t
--- response_body
passed



=== TEST 17: verify jack
--- request
GET /hello
--- more_headers
Authorization: Basic amFjazoxMjM0NTY=
--- error_code: 403



=== TEST 18: verify rose
--- request
GET /hello
--- more_headers
Authorization: Basic cm9zZToxMjM0NTY=
--- response_body
hello world



=== TEST 19: test acl with external user
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "serverless-pre-function": {
                                "phase": "access",
                                "functions" : ["return function(conf, ctx)
                                            local core = require(\"apisix.core\");
                                            local uri_args = core.request.get_uri_args(ctx) or {};
                                            if type(uri_args.team) == \"table\" then ctx.external_user = { team = uri_args.team } else ctx.external_user = { team = { uri_args.team } } end;
                                            end"]
                            },
                            "acl": {
                                 "external_user_label_field": "team",
                                 "allow_labels": {
                                    "team": ["cloud","infra","devops","qa"]
                                 }
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
--- request
GET /t
--- response_body
passed



=== TEST 20: verify infra team
--- request
GET /hello?team=infra
--- response_body
hello world



=== TEST 21: verify infra & fake team
--- request
GET /hello?team=infra&team=fake
--- response_body
hello world



=== TEST 22: verify fake team
--- request
GET /hello?team=fake
--- error_code: 403



=== TEST 23: set acl with external user parsed by JSONPath (parser is table)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "serverless-pre-function": {
                              "functions": [
                                "return function(conf, ctx)      ctx.external_user = { orgs = { api7 = { team = {\"cloud\", \"infra\"} } } };     end"
                              ],
                              "phase": "access"
                            },
                            "acl": {
                              "allow_labels": {
                                "org": ["api7", "apache"],
                                "team": ["cloud", "infra"]
                              },
                              "external_user_label_field": "$.orgs..team",
                              "external_user_label_field_key": "team",
                              "external_user_label_field_parser": "table",
                              "rejected_code": 403
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
--- request
GET /t
--- response_body
passed



=== TEST 24: test acl with external user parsed by JSONPath (parser is table)
--- request
GET /hello
--- response_body
hello world



=== TEST 25: set acl with external user parsed by JSONPath (parser is segmented_text)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "serverless-pre-function": {
                              "functions": [
                                "return function(conf, ctx)      ctx.external_user = { orgs = { api7 = { team = \"cloud|infra\" } } };     end"
                              ],
                              "phase": "access"
                            },
                            "acl": {
                              "allow_labels": {
                                "org": ["api7", "apache"],
                                "team": ["cloud", "infra"]
                              },
                              "external_user_label_field": "$.orgs..team",
                              "external_user_label_field_key": "team",
                              "external_user_label_field_parser": "segmented_text",
                              "external_user_label_field_separator": "\\|",
                              "rejected_code": 403
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
--- request
GET /t
--- response_body
passed



=== TEST 26: test acl with external user parsed by JSONPath (parser is segmented_text)
--- request
GET /hello
--- response_body
hello world



=== TEST 27: set acl with external user parsed by JSONPath (parser is json)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "serverless-pre-function": {
                              "functions": [
                                "return function(conf, ctx)      ctx.external_user = { orgses = { api7 = { team = \"[\\\"cloud\\\", \\\"infra\\\"]\" } } };     end"
                              ],
                              "phase": "access"
                            },
                            "acl": {
                              "allow_labels": {
                                "org": ["api7", "apache"],
                                "team": ["cloud", "infra"]
                              },
                              "external_user_label_field": "$..team",
                              "external_user_label_field_key": "team",
                              "external_user_label_field_parser": "json",
                              "rejected_code": 403
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
--- request
GET /t
--- response_body
passed



=== TEST 28: test acl with external user parsed by JSONPath (parser is json)
--- request
GET /hello
--- response_body
hello world



=== TEST 29: set acl parser "segmented_text", but can not extract expect value by the invalid separator
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "serverless-pre-function": {
                            "functions": [
                              "return function(conf, ctx)      ctx.external_user = { orgs = { api7 = { team = \"cloud|infra\" } } };     end"
                            ],
                            "phase": "access"
                            },
                            "acl": {
                              "allow_labels": {
                                "org": ["api7", "apache"],
                                "team": ["cloud", "infra"]
                              },
                              "external_user_label_field": "$.orgs..team",
                              "external_user_label_field_key": "team",
                              "external_user_label_field_parser": "segmented_text",
                              "external_user_label_field_separator": "|",
                              "rejected_code": 403
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
--- request
GET /t
--- response_body
passed



=== TEST 30: test ACL with the invalid separator
# User may want to split the text "cloud|infra" to be ["cloud", "infra"] by char "|", but it does not.
# Because the char "|" is a regex expression, the text "cloud|infra" will be split to ['c','l','o','u','d','|','i','n','f','r','a'].
# If you want to split text by "|" you should use "\\|".
# This is a normal case, no error_log here.
--- request
GET /hello
--- error_code: 403



=== TEST 31: set external_user info that ACL can extract multiple values from it.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "serverless-pre-function": {
                              "functions": [
                                "return function(conf, ctx)      ctx.external_user = { orgs = { api7 = { team = \"cloud|infra\" }, apache = { team = { \"devops\", \"qa\" } } } };     end"
                              ],
                              "phase": "access"
                            },
                            "acl": {
                              "allow_labels": {
                                "org": ["api7", "apache"],
                                "team": ["cloud", "infra"]
                              },
                              "external_user_label_field": "$.orgs..team",
                              "external_user_label_field_key": "team",
                              "external_user_label_field_parser": "segmented_text",
                              "external_user_label_field_separator": "\\|",
                              "rejected_code": 403
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
--- request
GET /t
--- response_body
passed



=== TEST 32: test the ACL extract multiple values from external_user info and the first value can not be expected.
# User may expect the value extracted is "cloud|infra", but it is not.
# Because the values extracted are multiple, we can not expect the value "cloud|infra" is the first.
# This is a normal case, no error_log here.
--- request
GET /hello
--- error_code: 403



=== TEST 33: use JSONPath to extract value but a correct external_user_label_field and external_user_label_field_parser is missing.
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "serverless-pre-function": {
                              "functions": [
                                "return function(conf, ctx)      ctx.external_user = { orgs = { api7 = { team = \"cloud,infra\" } } };     end"
                              ],
                              "phase": "access"
                            },
                            "acl": {
                              "allow_labels": {
                                "org": ["api7", "apache"],
                                "team": ["cloud", "infra"]
                              },
                              "external_user_label_field": "$..team",
                              "rejected_code": 403
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
--- request
GET /t
--- response_body
passed



=== TEST 34: test using JSONPath but a label key is missing.
# Using the JSONPath "$..team" to extract value and a label key is missing, the ACL will use the JSONPath as the key to match labels.
# It's obvious that our use of "$. .team" does not match any value in ACL allow_labels/deny_labels.
# This is a normal case, no error_log here.
--- request
GET /hello
--- error_code: 403



=== TEST 35: set invalid separator
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "serverless-pre-function": {
                              "functions": [
                                "return function(conf, ctx)      ctx.external_user = { orgs = { api7 = { team = \"cloud,infra\" } } };     end"
                              ],
                              "phase": "access"
                            },
                            "acl": {
                               "allow_labels": {
                                 "org": ["api7", "apache"],
                                 "team": ["cloud", "infra"]
                               },
                               "external_user_label_field": "$..team",
                               "external_user_label_field_key": "team",
                               "external_user_label_field_parser": "segmented_text",
                               "external_user_label_field_separator": "(invalid(pattern",
                               "rejected_code": 403
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
--- request
GET /t
--- response_body
passed



=== TEST 36: test invalid separator, ngx.re.split will be fail.
# The value extracted is "cloud,infra",
# ACL parser try to parser it as Lua table.
# It will fail and forbidden all.
--- request
GET /hello
--- error_code: 403
--- error_log eval
qr/failed to split labels \[cloud,infra\]/



=== TEST 37: set the parser "table" but the type of the value extracted is not a table
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "serverless-pre-function": {
                              "functions": [
                                "return function(conf, ctx)      ctx.external_user = { orgs = { api7 = { team = \"cloud,infra\" } } };     end"
                              ],
                              "phase": "access"
                            },
                            "acl": {
                              "allow_labels": {
                                "org": ["api7", "apache"],
                                "team": ["cloud", "infra"]
                              },
                              "external_user_label_field": "$..team",
                              "external_user_label_field_key": "team",
                              "external_user_label_field_parser": "table",
                              "rejected_code": 403
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
--- request
GET /t
--- response_body
passed



=== TEST 38: test the parser is "table" but the type of the value extracted is not a table
# The value extracted is "cloud,infra",
# ACL parser try to parser it as Lua table.
# It will fail and forbidden all.
--- request
GET /hello
--- error_code: 403
--- error_log
extra_values_with_parser(): the parser is specified as table, but the type of value is not table: string



=== TEST 39: set the parser "json" but the type of the value extracted is not string
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "serverless-pre-function": {
                              "functions": [
                                "return function(conf, ctx)      ctx.external_user = { orgs = { api7 = { team = {\"cloud\", \"infra\"} } } };     end"
                              ],
                              "phase": "access"
                            },
                            "acl": {
                              "allow_labels": {
                                "org": ["api7", "apache"],
                                "team": ["cloud", "infra"]
                              },
                              "external_user_label_field": "$..team",
                              "external_user_label_field_key": "team",
                              "external_user_label_field_parser": "json",
                              "rejected_code": 403
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
--- request
GET /t
--- response_body
passed



=== TEST 40: test the parser is "json" but the type of the value extracted is not string
# The value extracted is {"cloud", "infra"}, a Lua table.
# The ACL try to parser it as a serialized JSON.
# It will fail and forbidden all.
--- request
GET /hello
--- error_code: 403
--- error_log
extra_values_with_parser(): the parser is specified as json array, but the value type is not string



=== TEST 41: set the parser "json" but the value extracted has no prefix "["
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "serverless-pre-function": {
                              "functions": [
                                "return function(conf, ctx)      ctx.external_user = { orgs = { api7 = { team = \"cloud\" } } };     end"
                              ],
                              "phase": "access"
                            },
                            "acl": {
                              "allow_labels": {
                                "org": ["api7", "apache"],
                                "team": ["cloud", "infra"]
                              },
                              "external_user_label_field": "$..team",
                              "external_user_label_field_key": "team",
                              "external_user_label_field_parser": "json",
                              "rejected_code": 403
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
--- request
GET /t
--- response_body
passed



=== TEST 42: test the parser is "json" but the value extracted has no prefix "["
# The value extracted is "cloud".
# The ACL try to parse it as a serialized JSON string.
# It will fail and forbidden all.
--- request
GET /hello
--- error_code: 403
--- error_log
extra_values_with_parser(): the parser is specified as json array, but the value do not has prefix '['



=== TEST 43: set the parser "json" and the value extracted has prefix "[" but it is a invalid JSON
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "serverless-pre-function": {
                              "functions": [
                                "return function(conf, ctx)      ctx.external_user = { orgs = { api7 = { team = \"[cloud\" } } };     end"
                              ],
                              "phase": "access"
                            },
                            "acl": {
                              "allow_labels": {
                                "org": ["api7", "apache"],
                                "team": ["cloud", "infra"]
                              },
                              "external_user_label_field": "$..team",
                              "external_user_label_field_key": "team",
                              "external_user_label_field_parser": "json",
                              "rejected_code": 403
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
--- request
GET /t
--- response_body
passed



=== TEST 44: test the parser is "json" and the value extracted has prefix "[" but it is a invalid JSON
# The value extracted is "cloud".
# The ACL try to parse it as a serialized JSON string.
# It will fail and forbidden all.
--- request
GET /hello
--- error_code: 403
--- error_log
extra_values_with_parser(): failed to decode labels [[cloud] as array, err: Expected value but found invalid token at character 2



=== TEST 45: set no parser, value has no prefix "[" and no separator ",", external_user_label_field as labels key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "serverless-pre-function": {
                              "functions": [
                                "return function(conf, ctx)      ctx.external_user = { team = \"cloud\" };     end"
                              ],
                              "phase": "access"
                            },
                            "acl": {
                              "allow_labels": {
                                "org": ["api7", "apache"],
                                "team": ["cloud", "infra"]
                              },
                              "external_user_label_field": "team",
                              "rejected_code": 403
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
--- request
GET /t
--- response_body
passed



=== TEST 46: test no parser, value has no prefix "[" and no separator ",", external_user_label_field as labels key
# The value extracted is "cloud".
# There is no parser and the value type is "string", so ACL treat it as a Lua table {"cloud"}.
# It can match the ACL allow_labels, so response 200 OK.
--- request
GET /hello
--- response_body
hello world
--- log_level: info
--- error_log
extra_values_without_parser(): the string value can not parsed by json or segmented_text



=== TEST 47: TEST SCHEMA: invalid external_user_label_field_parser
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "acl": {
                              "allow_labels": {
                                "org": ["api7", "apache"],
                                "team": ["cloud", "infra"]
                              },
                              "external_user_label_field": "team",
                              "external_user_label_field_parser": "an-invalid-parser",
                              "rejected_code": 403
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
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin acl err: property \"external_user_label_field_parser\" validation failed: matches none of the enum values"}



=== TEST 48: TEST SCHEMA: external_user_label_field_parser="segmented_text" but external_user_label_field_separator is missing
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "acl": {
                              "allow_labels": {
                                "org": ["api7", "apache"],
                                "team": ["cloud", "infra"]
                              },
                              "external_user_label_field": "team",
                              "external_user_label_field_parser": "segmented_text",
                              "rejected_code": 403
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
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin acl err: allOf 1 failed: then clause did not match"}



=== TEST 49: TEST SCHEMA: invalid external_user_label_field_key (specified but empty)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "acl": {
                              "allow_labels": {
                                "org": ["api7", "apache"],
                                "team": ["cloud", "infra"]
                              },
                              "external_user_label_field": "team",
                              "external_user_label_field_parser": "segmented_text",
                              "external_user_label_field_key": "",
                              "rejected_code": 403
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
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin acl err: property \"external_user_label_field_key\" validation failed: string too short, expected at least 1, got 0"}



=== TEST 50: TEST SCHEMA: invalid external_user_label_field_key (specified but not string)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "acl": {
                              "allow_labels": {
                                "org": ["api7", "apache"],
                                "team": ["cloud", "infra"]
                              },
                              "external_user_label_field": "team",
                              "external_user_label_field_parser": "segmented_text",
                              "external_user_label_field_separator": {},
                              "rejected_code": 403
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
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin acl err: property \"external_user_label_field_separator\" validation failed: wrong type: expected string, got table"}



=== TEST 51: TEST SCHEMA: invalid external_user_label_field_separator (specified but empty)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "acl": {
                              "allow_labels": {
                                "org": ["api7", "apache"],
                                "team": ["cloud", "infra"]
                              },
                              "external_user_label_field": "team",
                              "external_user_label_field_parser": "segmented_text",
                              "external_user_label_field_separator": "",
                              "rejected_code": 403
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
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin acl err: property \"external_user_label_field_separator\" validation failed: string too short, expected at least 1, got 0"}



=== TEST 52: TEST SCHEMA: invalid external_user_label_field_separator (specified but not string)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "acl": {
                              "allow_labels": {
                                "org": ["api7", "apache"],
                                "team": ["cloud", "infra"]
                              },
                              "external_user_label_field": "team",
                              "external_user_label_field_parser": "segmented_text",
                              "external_user_label_field_separator": {},
                              "rejected_code": 403
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
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"failed to check the configuration of plugin acl err: property \"external_user_label_field_separator\" validation failed: wrong type: expected string, got table"}



=== TEST 53: TEST SCHEMA: invalid external_user_label_field (invalid JSONPath syntax)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "uri": "/hello",
                        "upstream": {
                            "type": "roundrobin",
                            "nodes": {
                                "127.0.0.1:1980": 1
                            }
                        },
                        "plugins": {
                            "acl": {
                              "allow_labels": {
                                "team": ["cloud"]
                              },
                              "external_user_label_field": "$..([invalid",
                              "rejected_code": 403
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
--- request
GET /t
--- error_code: 400
--- response_body_like
failed to check the configuration of plugin acl err: invalid external_user_label_field:



=== TEST 54: delete route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t( '/apisix/admin/routes/1', ngx.HTTP_DELETE )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 55: delete jack
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t( '/apisix/admin/consumers/jack', ngx.HTTP_DELETE )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 56: delete rose
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t( '/apisix/admin/consumers/rose', ngx.HTTP_DELETE )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
