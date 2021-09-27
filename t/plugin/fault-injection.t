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
log_level('info');
run_tests;

__DATA__

=== TEST 1: set route(invalid http_status in the abort property)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "abort": {
                                       "http_status": 100,
                                       "body": "Fault Injection!\n"
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
                               }
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
--- error_code: 400
--- response_body eval
qr/validation failed/
--- no_error_log
[error]



=== TEST 2: set route(without http_status in the abort property)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "abort": {
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
                               }
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
--- error_code: 400
--- response_body eval
qr/validation failed/
--- no_error_log
[error]



=== TEST 3: set route(without abort & delay properties)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
                               }
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
--- error_code: 400
--- response_body eval
qr/expect object to have at least 1 properties/
--- no_error_log
[error]



=== TEST 4: set route(without duration in the delay property)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "delay": {
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
                               }
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
--- error_code: 400
--- response_body eval
qr/validation failed/
--- no_error_log
[error]



=== TEST 5: set route(invalid duration with string in the delay property)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "delay": {
                                       "duration": "test"
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
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
--- error_code: 400
--- response_body eval
qr/wrong type: expected number, got string/
--- no_error_log
[error]



=== TEST 6: set route(invalid duration with double dot in the delay property)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "delay": {
                                       "duration": 0.1.1
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
                               }
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
--- error_code: 400
--- response_body eval
qr/invalid request body/
--- error_log eval
qr/invalid request body/



=== TEST 7: set route(invalid duration with whitespace in the delay property)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "delay": {
                                       "duration": 0. 1
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
                               }
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
--- error_code: 400
--- response_body eval
qr/invalid request body/
--- error_log eval
qr/invalid request body/



=== TEST 8: set route(invalid vars in the delay property)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                "delay": {
                                    "duration": 0.1,
                                    "vars": {
                                        "a",
                                        "b"
                                    }
                                },
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
                               }
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
--- error_code: 400
--- response_body eval
qr/invalid request body/
--- error_log eval
qr/invalid request body/



=== TEST 9: set route(invalid vars in in the abort property)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                    "abort": {
                                        "http_status": 200,
                                        "vars": {
                                            "a",
                                            "b"
                                        }
                                    }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
                               }
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
--- error_code: 400
--- response_body eval
qr/invalid request body/
--- error_log eval
qr/invalid request body/



=== TEST 10: set route(delay 1 seconds)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "delay": {
                                       "duration": 1
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
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
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]



=== TEST 11: hit route(delay 1 seconds and return hello world)
--- request
GET /hello HTTP/1.1
--- response_body
hello world
--- no_error_log
[error]



=== TEST 12: set route(abort with http status 200 and return "Fault Injection!\n")
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "abort": {
                                      "http_status": 200,
                                      "body": "Fault Injection!\n"
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
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
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]



=== TEST 13: hit route(abort with http code 200 and return "Fault Injection!\n")
--- request
GET /hello HTTP/1.1
--- error_code: 200
--- response_body
Fault Injection!
--- no_error_log
[error]



=== TEST 14: set route(abort with http status 405 and return "Fault Injection!\n")
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "abort": {
                                      "http_status": 405,
                                      "body": "Fault Injection!\n"
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello"
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
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]



=== TEST 15: hit route(abort with http status 405 and return "Fault Injection!\n")
--- request
GET /hello HTTP/1.1
--- error_code: 405
--- response_body
Fault Injection!
--- no_error_log
[error]



=== TEST 16: set route(play with redirect plugin)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "abort": {
                                      "http_status": 200,
                                      "body": "Fault Injection!\n"
                                   }
                               },
                               "redirect": {
                                   "uri": "/hello/world",
                                   "ret_code": 302
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
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]



=== TEST 17: hit route(abort with http status 200 and return "Fault Injection!\n")
--- request
GET /hello HTTP/1.1
--- error_code: 200
--- response_body
Fault Injection!
--- no_error_log
[error]



=== TEST 18: set route (abort injection but with zero percentage)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "abort": {
                                      "http_status": 200,
                                      "body": "Fault Injection!\n",
                                      "percentage": 0
                                   }
                               },
                               "redirect": {
                                   "uri": "/hello/world",
                                   "ret_code": 302
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
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]



=== TEST 19: hit route (redirect)
--- request
GET /hello HTTP/1.1
--- error_code: 302
--- no_error_log
[error]



=== TEST 20: set route (delay injection but with zero percentage)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                           "plugins": {
                               "fault-injection": {
                                   "delay": {
                                       "duration": 1,
                                       "percentage": 0
                                   }
                               },
                               "proxy-rewrite": {
                                   "uri": "/hello1"
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
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]



=== TEST 21: hit route (no wait and return hello1 world)
--- request
GET /hello HTTP/1.1
--- error_code: 200
--- response_body
hello1 world
--- no_error_log
[error]



=== TEST 22: set route(body with var)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                    "plugins": {
                        "fault-injection": {
                            "abort": {
                                "http_status": 200,
                                "body": "client addr: $remote_addr\n"
                            }
                        },
                        "proxy-rewrite": {
                            "uri": "/hello"
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
--- no_error_log
[error]



=== TEST 23: hit route(body with var)
--- request
GET /hello
--- response_body
client addr: 127.0.0.1
--- no_error_log
[error]



=== TEST 24: set route(abort without body)
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [[{
                    "plugins": {
                        "fault-injection": {
                            "abort": {
                                "http_status": 200
                            }
                        },
                        "proxy-rewrite": {
                            "uri": "/hello"
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
--- no_error_log
[error]



=== TEST 25: hit route(abort without body)
--- request
GET /hello
--- response_body
--- no_error_log
[error]



=== TEST 26: vars schema validation passed
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.fault-injection")
            local ok, err = plugin.check_schema({
                abort = {
                    http_status = 403,
                    body = "Fault Injection!\n",
                    vars = {
                        {
                            {"arg_name","==","jack"},
                            {"arg_age","!","<",18}
                        },
                        {
                            {"http_apikey","==","api-key"}
                        }
                    }
                },
                delay = {
                    duration = 2,
                    vars = {
                        {
                            {"arg_name","==","jack"},
                            {"arg_age","!","<",18}
                        },
                        {
                            {"http_apikey","==","api-key"}
                        }
                    }
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]



=== TEST 27: vars schema validation failed(abort failed)
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.fault-injection")
            local ok, err = plugin.check_schema({
                abort = {
                    http_status = 403,
                    body = "Fault Injection!\n",
                    vars = {
                        {"arg_name","!=","jack"}
                    }
                },
                delay = {
                    duration = 2,
                    vars = {
                        {
                            {"arg_name","==","jack"},
                            {"arg_age","!","<",18}
                        },
                        {
                            {"http_apikey","==","api-key"}
                        }
                    }
                }
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
rule should be wrapped inside brackets
done
--- error_log eval
qr/failed to create vars expression:.*/



=== TEST 28: set route and configure the vars rule in abort
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [=[{
                           "plugins": {
                               "fault-injection": {
                                   "abort": {
                                        "http_status": 403,
                                        "body": "Fault Injection!\n",
                                        "vars": [
                                            [
                                                ["arg_name","==","jack"],
                                                [ "arg_age","!","<",18 ]
                                            ],
                                            [
                                                [ "http_apikey","==","api-key" ]
                                            ]
                                        ]
                                   }
                               }
                           },
                           "upstream": {
                               "nodes": {
                                   "127.0.0.1:1980": 1
                               },
                               "type": "roundrobin"
                           },
                           "uri": "/hello"
                   }]=]
                   )
               if code >= 300 then
                   ngx.status = code
               end
               ngx.say(body)
           }
       }
--- request
GET /t
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]



=== TEST 29: hit the route (all vars rules pass), execute abort
--- request
GET /hello?name=jack&age=18
--- more_headers
apikey: api-key
--- error_code: 403
--- response_body
Fault Injection!
--- no_error_log
[error]



=== TEST 30: hit the route (missing apikey), execute abort
--- request
GET /hello?name=jack&age=20
--- error_code: 403
--- response_body
Fault Injection!
--- no_error_log
[error]



=== TEST 31: hit the route (missing request parameters), execute abort
--- request
GET /hello
--- more_headers
apikey:api-key
--- error_code: 403
--- response_body
Fault Injection!
--- no_error_log
[error]



=== TEST 32: hit route(`vars` do not match, `age` is missing)
--- request
GET /hello?name=allen
--- response_body
hello world
--- no_error_log
[error]



=== TEST 33: hit route(all `vars` do not match)
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 34: set route and configure the vars rule in delay
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [=[{
                        "uri": "/hello",
                        "plugins": {
                            "fault-injection": {
                                "delay": {
                                    "duration": 2,
                                    "vars": [
                                        [
                                            ["arg_name","==","jack"],
                                            [ "arg_age","!","<",18 ]
                                        ]
                                    ]
                                }
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        }
                   }]=]
                   )
               if code >= 300 then
                   ngx.status = code
               end
               ngx.say(body)
           }
       }
--- request
GET /t
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]



=== TEST 35: hit route(delay 2 seconds and return hello world)
--- request
GET /hello?name=jack&age=22
--- response_body
hello world
--- no_error_log
[error]



=== TEST 36: hit route (no wait and return hello1 world)
--- request
GET /hello HTTP/1.1
--- error_code: 200
--- response_body
hello world
--- no_error_log
[error]



=== TEST 37: set route and configure the vars rule in abort and delay
--- config
       location /t {
           content_by_lua_block {
               local t = require("lib.test_admin").test
               local code, body = t('/apisix/admin/routes/1',
                    ngx.HTTP_PUT,
                    [=[{
                           "plugins": {
                               "fault-injection": {
                                   "abort": {
                                        "http_status": 403,
                                        "body": "Fault Injection!\n",
                                        "vars": [
                                            [
                                                ["arg_name","==","jack"],
                                                ["arg_age","!","<",18]
                                            ]
                                        ]
                                   },
                                   "delay": {
                                    "duration": 2,
                                    "vars": [
                                        [
                                            ["http_apikey","==","api-key"]
                                        ]
                                    ]
                                }
                               }
                           },
                           "upstream": {
                               "nodes": {
                                   "127.0.0.1:1980": 1
                               },
                               "type": "roundrobin"
                           },
                           "uri": "/hello"
                   }]=]
                   )
               if code >= 300 then
                   ngx.status = code
               end
               ngx.say(body)
           }
       }
--- request
GET /t
--- error_code: 200
--- response_body
passed
--- no_error_log
[error]



=== TEST 38: hit the route (all vars rules are passed), execute abort and delay
--- request
GET /hello?name=jack&age=18
--- more_headers
apikey: api-key
--- error_code: 403
--- response_body
Fault Injection!
--- no_error_log
[error]



=== TEST 39: hit the route (abort rule does not match), only execute delay
--- request
GET /hello?name=jack&age=16
--- more_headers
apikey: api-key
--- response_body
hello world
--- no_error_log
[error]
