use t::APISIX 'no_plan';

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: Setup consumers
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test

        -- Create 'user' consumer
        local code, body = t('/apisix/admin/consumers',
            ngx.HTTP_PUT,
            [[{
                "username": "user",
                "plugins": {
                    "key-auth": {
                        "key": "user-key"
                    }
                }
            }]]
        )

        -- Create 'admin' consumer
        local code, body = t('/apisix/admin/consumers',
            ngx.HTTP_PUT,
            [[{
                "username": "admin",
                "plugins": {
                    "key-auth": {
                        "key": "admin-key"
                    }
                }
            }]]
        )

        ngx.say(body)
    }
}
--- response_body
passed



=== TEST 2: setup route with both allow and deny with match_all_roles
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
                        "ai-prompt-guard": {
														"match_all_roles": true,
                            "allow_patterns": [
															"goodword"
														],
														"deny_patterns": [
															"badword"
														]
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
--- response_body
passed



=== TEST 3: send request with good word
--- request
POST /hello
{
	"messages": [
		{ "role": "system", "content": "goodword" }
	]
}



=== TEST 4: send request with bad word
--- request
POST /hello
{
	"messages": [
		{ "role": "system", "content": "badword" }
	]
}
--- response_body
{"message":"Request doesn't match allow patterns"}
--- error_code: 400



=== TEST 5: setup route with only deny with match_all_roles
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
                        "ai-prompt-guard": {
														"match_all_roles": true,
														"deny_patterns": [
															"badword"
														]
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
--- response_body
passed



=== TEST 6: send request with good word
--- request
POST /hello
{
	"messages": [
		{ "role": "system", "content": "goodword" }
	]
}



=== TEST 7: send request with bad word
--- request
POST /hello
{
	"messages": [
		{ "role": "system", "content": "badword" }
	]
}
--- response_body
{"message":"Request contains prohibited content"}
--- error_code: 400



=== TEST 8: setup route with only allow with match_all_roles=false
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
                        "ai-prompt-guard": {
														"allow_patterns": [
															"goodword"
														]
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
--- response_body
passed



=== TEST 9: send request with bad word and it will pass for non user
--- request
POST /hello
{
	"messages": [
		{ "role": "system", "content": "badword" }
	]
}



=== TEST 10: send request with bad word
--- request
POST /hello
{
	"messages": [
		{ "role": "user", "content": "badword" }
	]
}
--- response_body
{"message":"Request doesn't match allow patterns"}
--- error_code: 400



=== TEST 11: setup route with only deny with match_all_conversation_history
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
                        "ai-prompt-guard": {
														"match_all_conversation_history": true,
														"match_all_roles": true,
														"deny_patterns": [
															"badword"
														]
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
--- response_body
passed



=== TEST 12: send request with good word but had bad word in history
--- request
POST /hello
{
	"messages": [
		{ "role": "system", "content": "goodword" },
		{ "role": "system", "content": "badword" },
		{ "role": "system", "content": "goodword" }
	]
}
--- response_body
{"message":"Request contains prohibited content"}
--- error_code: 400



=== TEST 13: setup route with only deny with match_all_conversation_history=false
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
                        "ai-prompt-guard": {
														"match_all_conversation_history": false,
														"match_all_roles": true,
														"deny_patterns": [
															"badword"
														]
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
--- response_body
passed



=== TEST 14: send request with good word but had bad word in history
--- request
POST /hello
{
	"messages": [
		{ "role": "system", "content": "goodword" },
		{ "role": "system", "content": "badword" },
		{ "role": "system", "content": "goodword" }
	]
}
