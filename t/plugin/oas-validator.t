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
});

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local plugin = require("apisix.plugins.oas-validator")
            local ospec = t.read_file("t/spec/spec.json")

            local ok, err = plugin.check_schema({spec = ospec})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: open api string should be json
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.oas-validator")
            local ok, err = plugin.check_schema({spec = "invalid json string"})
            ngx.say(err)
        }
    }
--- response_body
invalid JSON string provided, err: Expected value but found invalid token at character 1



=== TEST 3: create route correctly
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec.json")
            spec = spec:gsub('\"', '\\"')

            local code, body = t.test('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 string.format([[{
                     "uri": "/*",
                     "plugins": {
                       "oas-validator": {
                         "spec": "%s"
                       }
                     },
                     "upstream": {
                       "type": "roundrobin",
                       "nodes": {
                         "127.0.0.1:6969": 1
                       }
                     }
                }]], spec)
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: test body validation -- POST
--- request
POST /api/v3/pet
{"id": 10, "name": "doggie", "category": {"id": 1, "name": "Dogs"}, "photoUrls": ["string"], "tags": [{"id": 1, "name": "tag1"}], "status": "available"}
--- more_headers
Content-Type: application/json
--- no_error_log
[error]



=== TEST 5: test body validation -- PUT
--- request
PUT /api/v3/pet
{"id": 10, "name": "doggie", "category": { "id": 1, "name": "Dogs"}, "photoUrls": [ "string"], "tags": [{ "id": 0, "name": "string"}], "status": "available"}
--- more_headers
Content-Type: application/json
--- no_error_log
[error]



=== TEST 6: passing incorrect body should fail
--- request
POST /api/v3/pet
{"lol": "watdis?"}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 7: test body validation with Query Params
--- request
GET /api/v3/pet/findByStatus?status=pending
--- more_headers
Content-Type: application/json
--- no_error_log
[error]



=== TEST 8: querying for married dogs should fail (incorrect query param)
--- request
GET /api/v3/pet/findByStatus?status=married
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 9: test body validation with Path Params
--- request
GET /api/v3/pet/10
--- more_headers
Content-Type: application/json
--- no_error_log
[error]



=== TEST 10: querying with wrong path uri param should fail
--- request
GET /api/v3/pet/wrong-id
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 11: create route for skipping body validation
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec.json")
            spec = spec:gsub('\"', '\\"')

            local code, body = t.test('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 string.format([[{
                     "uri": "/*",
                     "plugins": {
                       "oas-validator": {
                         "spec": "%s",
                         "skip_request_body_validation": true
                       }
                     },
                     "upstream": {
                       "type": "roundrobin",
                       "nodes": {
                         "127.0.0.1:1980": 1
                       },
                       "scheme": "http",
                       "pass_host": "pass"
                     }
                }]], spec)
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 12: passing incorrect body should pass validation (skip_request_body_validation = true)
--- request
POST /api/v3/pet
{"lol": "watdis?"}
--- more_headers
Content-Type: application/json
--- no_error_log
[error]



=== TEST 13: create route for skipping header validation
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec.json")
            spec = spec:gsub('\"', '\\"')

            local code, body = t.test('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 string.format([[{
                     "uri": "/*",
                     "plugins": {
                       "oas-validator": {
                         "spec": "%s",
                         "skip_request_header_validation": true
                       }
                     },
                     "upstream": {
                       "type": "roundrobin",
                       "nodes": {
                         "127.0.0.1:1980": 1
                       },
                       "scheme": "http",
                       "pass_host": "pass"
                     }
                }]], spec)
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 14: passing incorrect header should pass validation (skip_request_header_validation = true)
--- request
GET /api/v3/pet/1
--- more_headers
Content-Type: not-application/json
--- error_code: 200



=== TEST 15: create route for skipping query param validation
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec.json")
            spec = spec:gsub('\"', '\\"')

            local code, body = t.test('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 string.format([[{
                     "uri": "/*",
                     "plugins": {
                       "oas-validator": {
                         "spec": "%s",
                         "skip_query_param_validation": true
                       }
                     },
                     "upstream": {
                       "type": "roundrobin",
                       "nodes": {
                         "127.0.0.1:1980": 1
                       },
                       "scheme": "http",
                       "pass_host": "pass"
                     }
                }]], spec)
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 16: querying for incorrect query params should pass (skip_query_param_validation = true)
--- request
GET /api/v3/pet/findByStatus?status=married
--- more_headers
Content-Type: application/json
--- error_code: 200



=== TEST 17: create route for skipping path param validation
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec.json")
            spec = spec:gsub('\"', '\\"')

            local code, body = t.test('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 string.format([[{
                     "uri": "/*",
                     "plugins": {
                       "oas-validator": {
                         "spec": "%s",
                         "skip_path_params_validation": true
                       }
                     },
                     "upstream": {
                       "type": "roundrobin",
                       "nodes": {
                         "127.0.0.1:1980": 1
                       },
                       "scheme": "http",
                       "pass_host": "pass"
                     }
                }]], spec)
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 18: querying for incorrect path params should pass (skip_path_params_validation = true)
--- request
GET /api/v3/pet/incorrect-id
--- more_headers
Content-Type: application/json
--- error_code: 200



=== Test 19: test multipleOf validation
--- request
POST /api/v3/multipleoftest
{"testnumber": 1.13}
--- more_headers
Content-Type: application/json
--- no_error_log
[error]



=== Test 20: test multipleOf validation - invalid
--- request
POST /api/v3/multipleoftest
{"testnumber": 1.1312}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 21: route setup with reject_if_not_match = false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec.json")
            spec = spec:gsub('\"', '\\"')

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/*",
                    "plugins": {
                        "oas-validator": {
                            "spec": "%s",
                            "reject_if_not_match": false
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": { 
                            "127.0.0.1:1980": 1 
                        }
                    }
                }]], spec)
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 22: invalid body should still pass to upstream (reject_if_not_match is false)
--- upstream_server_config
    location /api/v3/pet {
        content_by_lua_block {
            ngx.log(ngx.WARN, "upstream reached")
            ngx.status = 200
            ngx.say("ok")
        }
    }
--- request
POST /api/v3/pet
{"lol": "watdis?"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- error_log
error occurred while validating request
--- grep_error_log eval
qr/upstream reached/
--- grep_error_log_out
upstream reached



=== TEST 23: create route with explicit reject_if_not_match = true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec.json")
            spec = spec:gsub('\"', '\\"')
            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/*",
                    "plugins": {
                        "oas-validator": {
                            "spec": "%s",
                            "reject_if_not_match": true
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:6969": 1
                        }
                    }
                }]], spec)
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 24: invalid body should be rejected when reject_if_not_match is true
--- request
POST /api/v3/pet
{"lol": "watdis?"}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 25: create route with rejection_status_code = 422
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec.json")
            spec = spec:gsub('\"', '\\"')

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/*",
                    "plugins": {
                        "oas-validator": {
                            "spec": "%s",
                            "reject_if_not_match": true,
                            "rejection_status_code": 422
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:6969": 1
                        }
                    }
                }]], spec)
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 26: invalid body should return 422 when rejection_status_code = 422
--- request
POST /api/v3/pet
{"lol": "watdis?"}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 422
--- error_log
error occurred while validating request



=== TEST 27: create route with rejection_status_code = 503
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec.json")
            spec = spec:gsub('\"', '\\"')

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/*",
                    "plugins": {
                        "oas-validator": {
                            "spec": "%s",
                            "reject_if_not_match": true,
                            "rejection_status_code": 503
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:6969": 1
                        }
                    }
                }]], spec)
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 28: invalid body should return 503 when rejection_status_code = 503
--- request
POST /api/v3/pet
{"lol": "watdis?"}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 503
--- error_log
error occurred while validating request



=== TEST 29: schema should reject rejection_status_code = 399 (out of range)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec.json")
            spec = spec:gsub('\"', '\\"')

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/*",
                    "plugins": {
                        "oas-validator": {
                            "spec": "%s",
                            "rejection_status_code": 399
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:6969": 1
                        }
                    }
                }]], spec)
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body_like: validation failed



=== TEST 30: schema should reject rejection_status_code = 600 (out of range)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec.json")
            spec = spec:gsub('\"', '\\"')

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/*",
                    "plugins": {
                        "oas-validator": {
                            "spec": "%s",
                            "rejection_status_code": 600
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:6969": 1
                        }
                    }
                }]], spec)
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- error_code: 400
--- response_body_like: validation failed



=== TEST 31: boundary value rejection_status_code = 400 should be accepted
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec.json")
            spec = spec:gsub('\"', '\\"')

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/*",
                    "plugins": {
                        "oas-validator": {
                            "spec": "%s",
                            "rejection_status_code": 400
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:6969": 1
                        }
                    }
                }]], spec)
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 32: boundary value rejection_status_code = 599 should be accepted
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec.json")
            spec = spec:gsub('\"', '\\"')

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/*",
                    "plugins": {
                        "oas-validator": {
                            "spec": "%s",
                            "rejection_status_code": 599
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:6969": 1
                        }
                    }
                }]], spec)
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 33: rejection_status_code should not affect behavior when reject_if_not_match = false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec.json")
            spec = spec:gsub('\"', '\\"')

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/*",
                    "plugins": {
                        "oas-validator": {
                            "spec": "%s",
                            "reject_if_not_match": false,
                            "rejection_status_code": 422
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1980": 1
                        }
                    }
                }]], spec)
            )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 34: invalid body should pass to upstream when reject_if_not_match = false (rejection_status_code ignored)
--- upstream_server_config
    location /api/v3/pet {
        content_by_lua_block {
            ngx.log(ngx.WARN, "upstream reached")
            ngx.status = 200
            ngx.say("ok")
        }
    }
--- request
POST /api/v3/pet
{"lol": "watdis?"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- error_log
error occurred while validating request
--- grep_error_log eval
qr/upstream reached/
--- grep_error_log_out
upstream reached
