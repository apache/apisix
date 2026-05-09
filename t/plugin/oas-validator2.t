use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    my $http_config = $block->http_config // <<_EOC_;
    # fake server, only for test
    server {
        listen 1970;
        location / {
            content_by_lua_block {
                ngx.say("ok")
            }
        }
    }
_EOC_

    $block->set_value("http_config", $http_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: OAS 3.1 -- create route with spec31.json
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec31.json")
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
                            "127.0.0.1:1970": 1
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



=== TEST 2: OAS 3.1 exclusiveMinimum/Maximum (numeric) -- value within range should pass
--- request
POST /api/v31/exclusive
{"score": 50}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 3: OAS 3.1 exclusiveMinimum -- value equal to lower bound (0) should fail
--- request
POST /api/v31/exclusive
{"score": 0}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 4: OAS 3.1 exclusiveMaximum -- value equal to upper bound (100) should fail
--- request
POST /api/v31/exclusive
{"score": 100}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 5: OAS 3.1 if/then/else -- circle with radius should pass (then branch)
--- request
POST /api/v31/shape
{"type": "circle", "radius": 5}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 6: OAS 3.1 if/then -- circle without radius should fail
--- request
POST /api/v31/shape
{"type": "circle"}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 7: OAS 3.1 if/else -- rectangle with width and height should pass (else branch)
--- request
POST /api/v31/shape
{"type": "rectangle", "width": 10, "height": 5}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 8: OAS 3.1 if/else -- rectangle missing width should fail
--- request
POST /api/v31/shape
{"type": "rectangle", "height": 5}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 9: OAS 3.1 anyOf -- matching first subschema should pass
--- request
POST /api/v31/anyof
{"name": "doggie"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 10: OAS 3.1 anyOf -- matching second subschema should pass
--- request
POST /api/v31/anyof
{"id": 42}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 11: OAS 3.1 anyOf -- matching neither subschema should fail
--- request
POST /api/v31/anyof
{"other": "value"}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 12: OAS 3.1 oneOf -- matching exactly one subschema should pass
--- request
POST /api/v31/oneof
{"cat": "whiskers"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 13: OAS 3.1 oneOf -- matching both subschemas should fail
--- request
POST /api/v31/oneof
{"cat": "whiskers", "dog": "rex"}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 14: OAS 3.1 allOf -- all subschemas satisfied should pass
--- request
POST /api/v31/allof
{"a": "hello", "b": 42}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 15: OAS 3.1 allOf -- missing field required by one subschema should fail
--- request
POST /api/v31/allof
{"a": "hello"}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 16: OAS 3.1 -- route with spec31.json and reject_if_not_match = false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec31.json")
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



=== TEST 17: OAS 3.1 reject_if_not_match = false -- invalid body passes through to upstream
--- upstream_server_config
    location /api/v31/pet {
        content_by_lua_block {
            ngx.log(ngx.WARN, "upstream reached")
            ngx.status = 200
            ngx.say("ok")
        }
    }
--- request
POST /api/v31/pet
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



=== TEST 18: OAS 3.1 -- route with spec31.json and rejection_status_code = 422
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec31.json")
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
                            "127.0.0.1:1970": 1
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



=== TEST 19: OAS 3.1 rejection_status_code = 422 -- invalid body returns 422
--- request
POST /api/v31/pet
{"lol": "watdis?"}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 422
--- error_log
error occurred while validating request



=== TEST 20: OAS 3.1 -- route with spec31.json and verbose_errors = true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec31.json")
            spec = spec:gsub('\"', '\\"')

            local code, body = t.test('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                string.format([[{
                    "uri": "/*",
                    "plugins": {
                        "oas-validator": {
                            "spec": "%s",
                            "verbose_errors": true
                        }
                    },
                    "upstream": {
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:1970": 1
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



=== TEST 21: OAS 3.1 verbose_errors = true -- error response body contains schema detail
--- request
POST /api/v31/pet
{"lol": "watdis?"}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request\..+
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 22: OAS 3.1 -- route with spec31.json and skip_request_body_validation = true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec31.json")
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



=== TEST 23: OAS 3.1 skip_request_body_validation = true -- invalid body is not rejected
--- request
POST /api/v31/pet
{"lol": "watdis?"}
--- more_headers
Content-Type: application/json
--- no_error_log
[error]



=== TEST 24: OAS 3.1 -- route with spec31.json and skip_query_param_validation = true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec31.json")
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



=== TEST 25: OAS 3.1 skip_query_param_validation = true -- invalid enum query param is not rejected
--- request
GET /api/v31/pet/findByStatus?status=married
--- more_headers
Content-Type: application/json
--- error_code: 200



=== TEST 26: OAS 3.1 -- route with spec31.json and skip_path_params_validation = true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec31.json")
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



=== TEST 27: OAS 3.1 skip_path_params_validation = true -- non-integer path param is not rejected
--- request
GET /api/v31/pet/not-an-id
--- more_headers
Content-Type: application/json
--- error_code: 200



=== TEST 28: OAS 3.1 -- restore route with spec31.json (no extra options)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec31.json")
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
                            "127.0.0.1:1970": 1
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



=== TEST 29: OAS 3.1 body validation -- valid Pet passes plugin (upstream returns 404)
--- request
POST /api/v31/pet
{"name": "doggie", "photoUrls": ["http://example.com/img.jpg"]}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 30: OAS 3.1 body validation -- missing required field should fail
--- request
POST /api/v31/pet
{"name": "doggie"}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 31: OAS 3.1 path param validation -- valid integer id passes plugin
--- request
GET /api/v31/pet/42
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 32: OAS 3.1 path param validation -- non-integer id should fail
--- request
GET /api/v31/pet/not-an-id
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 33: OAS 3.1 query param validation -- valid enum value passes plugin
--- request
GET /api/v31/pet/findByStatus?status=available
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 34: OAS 3.1 query param validation -- invalid enum value should fail
--- request
GET /api/v31/pet/findByStatus?status=married
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 35: OAS 3.1 nullable type array -- null value should pass
--- request
POST /api/v31/nullable
{"value": null}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 36: OAS 3.1 nullable type array -- string value should pass
--- request
POST /api/v31/nullable
{"value": "hello"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 37: OAS 3.1 nullable type array -- integer value should fail
--- request
POST /api/v31/nullable
{"value": 123}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 38: OAS 3.1 const keyword -- correct value should pass
--- request
POST /api/v31/const
{"version": "v1"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 39: OAS 3.1 const keyword -- wrong value should fail
--- request
POST /api/v31/const
{"version": "v2"}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 40: OAS 3.1 multipleOf validation -- valid value passes
--- request
POST /api/v31/multipleoftest
{"testnumber": 1.13}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 41: OAS 3.1 multipleOf validation -- invalid value should fail
--- request
POST /api/v31/multipleoftest
{"testnumber": 1.1312}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 42: OAS 3.1 -- create route with spec31-gaps.json (components/pathItems, not, patternProperties, $dynamicRef)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local spec = t.read_file("t/spec/spec31-gaps.json")
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
                            "127.0.0.1:1970": 1
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



=== TEST 43: components/pathItems -- valid body via $ref path should pass
--- request
POST /api/v31gap/widget
{"name": "foo"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 44: components/pathItems -- invalid body via $ref path should fail
--- request
POST /api/v31gap/widget
{"notaname": "foo"}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 45: not keyword -- value satisfying not constraint should pass
--- request
POST /api/v31gap/item
{"value": "not-an-integer"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 46: not keyword -- value violating not constraint should fail
--- request
POST /api/v31gap/item
{"value": 42}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 47: patternProperties -- matching key with correct type should pass
--- request
POST /api/v31gap/pattern
{"S_name": "hello"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 48: patternProperties -- matching key with wrong type should fail
--- request
POST /api/v31gap/pattern
{"S_name": 123}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 49: patternProperties with additionalProperties:false -- non-matching key should be rejected
--- request
POST /api/v31gap/pattern
{"S_name": "hello", "extra": "not_allowed"}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 50: $dynamicRef -- array with correct element type should pass
--- request
POST /api/v31gap/dynref
{"items": ["hello", "world"]}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 51: $dynamicRef -- array with wrong element type should fail
--- request
POST /api/v31gap/dynref
{"items": [1, 2, 3]}
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 52: [LIMITATION] contentMediaType/contentEncoding are annotations only -- non-JSON string passes without content validation
--- request
POST /api/v31gap/content-annotation
{"data": "this is NOT valid base64 nor JSON"}
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 53: prefixItems -- correct positional types should pass
--- request
POST /api/v31gap/prefixitems
["hello", 42, true]
--- more_headers
Content-Type: application/json
--- error_code: 200
--- no_error_log
[error]



=== TEST 54: prefixItems -- wrong type at first position should fail
--- request
POST /api/v31gap/prefixitems
[123, 42, true]
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request



=== TEST 55: [LIMITATION] prefixItems + items -- extra items beyond prefixItems are validated by items schema
--- request
POST /api/v31gap/prefixitems
["hello", 42, "not_a_boolean"]
--- more_headers
Content-Type: application/json
--- response_body_like: failed to validate request.
--- error_code: 400
--- error_log
error occurred while validating request
