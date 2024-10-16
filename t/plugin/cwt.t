use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__



=== TEST 1: plugin field (usr) is missing
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.cwt")
            local ok, err = plugin.check_schema({wallet='123', exp=100}, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "usr" is required
done

=== TEST 2: plugin field (wallet) is missing
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.cwt")
            local ok, err = plugin.check_schema({usr='usr', exp=100}, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "wallet" is required
done

=== TEST 3: plugin field (exp) is missing
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.cwt")
            local ok, err = plugin.check_schema({usr='usr', wallet='abc'}, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "exp" is required
done

=== TEST 4: wrong type of plugin field (usr)
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.cwt")
            local ok, err = plugin.check_schema({usr=123, wallet='123', exp=100}, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "usr" validation failed: wrong type: expected string, got number
done

=== TEST 5: enable cwt plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "cwt": {}
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
--- response_body
passed

=== TEST 6: add 7 consumers
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "for_ripple_secp256k1",
                    "plugins": {
                        "cwt": {
                            "usr": "ripple_secp256k1",
                            "wallet": "r42EeCe73YsQsyNKxFFhkyRnV9tebHpcq",
                            "exp": 3153600000
                        }
                    }
                }]]
                )
            ngx.say("code: ", code < 300, ", body: ", body)

            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "for_ripple_ed25519",
                    "plugins": {
                        "cwt": {
                            "usr": "ripple_ed25519",
                            "wallet": "rDyv9dMqhaYvSFPFnTnZpK9TZsQG4QCHBn",
                            "exp": 3153600000
                        }
                    }
                }]]
                )
            ngx.say("code: ", code < 300, ", body: ", body)

            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "for_jingtum_secp256k1",
                    "plugins": {
                        "cwt": {
                            "usr": "jingtum_secp256k1",
                            "wallet": "jXhA8zUAj1LgCC3KXdb9kY8kj3xKLY64P",
                            "exp": 3153600000
                        }
                    }
                }]]
                )
            ngx.say("code: ", code < 300, ", body: ", body)

            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "for_jingtum_ed25519",
                    "plugins": {
                        "cwt": {
                            "usr": "jingtum_ed25519",
                            "wallet": "jp4nUEDsePuy4YGhwZT3g7X89kT1rFjPaF",
                            "exp": 3153600000
                        }
                    }
                }]]
                )
            ngx.say("code: ", code < 300, ", body: ", body)

            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "for_bitcoin",
                    "plugins": {
                        "cwt": {
                            "usr": "bitcoin",
                            "wallet": "1MDkajH1yRi3QQP7qijaPLKbr9x2AyvfUZ",
                            "exp": 3153600000
                        }
                    }
                }]]
                )
            ngx.say("code: ", code < 300, ", body: ", body)

            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "for_ethereum",
                    "plugins": {
                        "cwt": {
                            "usr": "ethereum",
                            "wallet": "0xac68efe4420cb0a20565903af0d441261d742192",
                            "exp": 3153600000
                        }
                    }
                }]]
                )
            ngx.say("code: ", code < 300, ", body: ", body)

            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "expired_token",
                    "plugins": {
                        "cwt": {
                            "usr": "ethereum2",
                            "wallet": "0xac68efe4420cb0a20565903af0d441261d742192",
                            "exp": 10
                        }
                    }
                }]]
                )
            ngx.say("code: ", code < 300, ", body: ", body)
        }
    }
--- response_body
code: true, body: passed
code: true, body: passed
code: true, body: passed
code: true, body: passed
code: true, body: passed
code: true, body: passed
code: true, body: passed

=== TEST 7: verify request with token in argument(ripple secp256k1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, _, res = t('/hello?cwt=eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1EWXdFQVlIS29aSXpqMENBUVlGSzRFRUFBb0RJZ0FDRVBqa0hyNzhkL0hLWStydEJKeUIzUmJ0Z2kzRkFDbEFcbmVLSkFjcmNrdTlNPVxuLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tIl0sInR5cGUiOiJDV1QiLCJjaGFpbiI6InJpcHBsZSIsImFsZyI6InNlY3AyNTZrMSJ9.eyJ1c3IiOiJyaXBwbGVfc2VjcDI1NmsxIiwidGltZSI6MTcyMDU5ODQ3MX0.MEQCID1jqPMeBdk5jTDWGMHteocpEnO2wCX8AbG7qrcFXwx2AiBfo7E0CVj6diW34CM9sisr3qyy2vdgLL5JYfExtHIyMw',
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world

=== TEST 8: verify request with token in argument(ripple ed25519)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, _, res = t('/hello?cwt=eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1Db3dCUVlESzJWd0F5RUFZSkQ4T1NTdWpYd0hienhBZFFNYUcvZXJkQVRtYllndTVmZVdmRjhRdWJZPVxuLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tXG4iXSwidHlwZSI6IkNXVCIsImNoYWluIjoicmlwcGxlIiwiYWxnIjoiZWQyNTUxOSJ9.eyJ1c3IiOiJyaXBwbGVfZWQyNTUxOSIsInRpbWUiOjE3MjA2MDM4NTR9.HXSvijqL-PzKoXiJ1eWiXrzXCBM9EHHSwE7wta779FDh3SyclXvvZOIx59jbDLwL3BpO5a7YwKZ1s6Jud8A2Cw',
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world

=== TEST 9: verify request with token in argument(jingtum secp256k1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, _, res = t('/hello?cwt=eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1EWXdFQVlIS29aSXpqMENBUVlGSzRFRUFBb0RJZ0FDVFRPdTBEdFF6OVY4ZXg4Yzk0dzlYTm13THI2YVNBTTVcblQveTB4R0RUbkZrPVxuLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tIl0sInR5cGUiOiJDV1QiLCJjaGFpbiI6Imppbmd0dW0iLCJhbGciOiJzZWNwMjU2azEifQ.eyJ1c3IiOiJqaW5ndHVtX3NlY3AyNTZrMSIsInRpbWUiOjE3MjA2ODEyODl9.MEYCIQCLorVH0yaQhTZL2cF5Sbpia4ntW9FBDNTL35ixQFcs1wIhAMmTVdmVc51Wn-UvpEju75qXj69CfbYxZKp3Dvtd8AVj',
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world

=== TEST 10: verify request with token in argument(jingtum ed25519)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, _, res = t('/hello?cwt=eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1Db3dCUVlESzJWd0F5RUFiaCtwTEx5emMyam5ZaDBWWStUeSszWndBT3FpcUh3RzErTlRRaldMY0RJPVxuLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tXG4iXSwidHlwZSI6IkNXVCIsImNoYWluIjoiamluZ3R1bSIsImFsZyI6ImVkMjU1MTkifQ.eyJ1c3IiOiJqaW5ndHVtX2VkMjU1MTkiLCJ0aW1lIjoxNzIwNjgxMzc3fQ.aNUydPEOwUD5xrwxdKtmZ3C7gmRlZiBZ-Guuti1NUyReysc-ZSNYcfsF3XZG6aY49ADwLExk3wuVClm6B1VjAA',
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world

=== TEST 11: verify request with token in argument(bitcoin)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, _, res = t('/hello?cwt=eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1GWXdFQVlIS29aSXpqMENBUVlGSzRFRUFBb0RRZ0FFckNTNk1PV1lOWjhuLzhOVlFDVmZLZlpaUytIRUtlcGhcbkJjcXFkVUhTZVNFcDR3KzFjRi9rTjA3Nmw0MmFEK1Y1L2JueE1wQ0orSnE4WmFlQUxIZldqZz09XG4tLS0tLUVORCBQVUJMSUMgS0VZLS0tLS0iXSwidHlwZSI6IkNXVCIsImNoYWluIjoiYml0Y29pbiIsImFsZyI6InNlY3AyNTZrMSJ9.eyJ1c3IiOiJiaXRjb2luIiwidGltZSI6MTcyMDY4MDYxN30.MEQCICe2Yuz9P8-XVT2Pb1QjIGfsgC_7E9ZqCEOiL8fB-cHCAiAOoe1pj_Ozq3mqsAIpJnDidJdJSBYCAymFN-DN9sO0Dw',
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world

=== TEST 12: verify request with token in argument(ethereum)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, _, res = t('/hello?cwt=eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1GWXdFQVlIS29aSXpqMENBUVlGSzRFRUFBb0RRZ0FFaWJpcmx6eEtnZ0EzNWp1TUNtSmRhbUNDZ0hhOE9ZSkdcbk9HMFlIRzYxMUk5UDdrTEFBYlNqNGg0SFJHeUNSZnA0Ky9ndkxtcGU1Uis3UFV2bDNHU0NvZz09XG4tLS0tLUVORCBQVUJMSUMgS0VZLS0tLS0iXSwidHlwZSI6IkNXVCIsImNoYWluIjoiZXRoZXJldW0iLCJhbGciOiJzZWNwMjU2azEifQ.eyJ1c3IiOiJldGhlcmV1bSIsInRpbWUiOjE3MjA3Nzc4OTR9.MEYCIQDaQJfYwRxJiaZFWTU9XXsUOoy_7ZN2DBpEEqVsg1XyogIhALQAI0ifh7ZX3YQZx2LJ7-Ky5Zw35WjVQgqu0MpOAnqD',
                ngx.HTTP_GET
            )

            ngx.status = code
            ngx.print(res)
        }
    }
--- response_body
hello world

=== TEST 13: verify request, missing token
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing cwt token in request"}
--- error_log
failed to fetch cwt token: Missing token

=== TEST 14: verify request, invalid token format
--- request
GET /hello?cwt=eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk.eyJ1c3IiOiJldGhlcmV1bSIsInRpbWUiOjE3MjA3Nzc4OTR9
--- error_code: 401
--- response_body
{"message":"cwt token invalid"}
--- error_log
cwt token invalid: invalid cwt string

=== TEST 15: verify request, invalid token header
--- request
GET /hello?cwt=eyJ4NWMiOls.eyJ1c3IiOiJldGhlcmV1bSIsInRpbWUiOjE3MjA3Nzc4OTR9.MEYCIQDaQJfYwRxJiaZFWTU9XXsUOoy_7ZN2DBpEEqVsg1XyogIhALQAI0ifh7ZX3YQZx2LJ7-Ky5Zw35WjVQgqu0MpOAnqD
--- error_code: 401
--- response_body
{"message":"cwt token invalid"}
--- error_log
cwt token invalid: invalid header: eyJ4NWMiOls

=== TEST 16: verify request, invalid token payload
--- request
GET /hello?cwt=eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1GWXdFQVlIS29aSXpqMENBUVlGSzRFRUFBb0RRZ0FFaWJpcmx6eEtnZ0EzNWp1TUNtSmRhbUNDZ0hhOE9ZSkdcbk9HMFlIRzYxMUk5UDdrTEFBYlNqNGg0SFJHeUNSZnA0Ky9ndkxtcGU1Uis3UFV2bDNHU0NvZz09XG4tLS0tLUVORCBQVUJMSUMgS0VZLS0tLS0iXSwidHlwZSI6IkNXVCIsImNoYWluIjoiZXRoZXJldW0iLCJhbGciOiJzZWNwMjU2azEifQ.eyJ1c3IiOiJl.MEYCIQDaQJfYwRxJiaZFWTU9XXsUOoy_7ZN2DBpEEqVsg1XyogIhALQAI0ifh7ZX3YQZx2LJ7-Ky5Zw35WjVQgqu0MpOAnqD
--- error_code: 401
--- response_body
{"message":"cwt token invalid"}
--- error_log
cwt token invalid: invalid payload: eyJ1c3IiOiJl

=== TEST 17: verify request, token has expired
--- request
GET /hello?cwt=eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1GWXdFQVlIS29aSXpqMENBUVlGSzRFRUFBb0RRZ0FFaWJpcmx6eEtnZ0EzNWp1TUNtSmRhbUNDZ0hhOE9ZSkdcbk9HMFlIRzYxMUk5UDdrTEFBYlNqNGg0SFJHeUNSZnA0Ky9ndkxtcGU1Uis3UFV2bDNHU0NvZz09XG4tLS0tLUVORCBQVUJMSUMgS0VZLS0tLS0iXSwidHlwZSI6IkNXVCIsImNoYWluIjoiZXRoZXJldW0iLCJhbGciOiJzZWNwMjU2azEifQ.eyJ1c3IiOiJldGhlcmV1bTIiLCJ0aW1lIjoxNzIxODg4ODA3fQ.MEQCIDP4vYa0jQGVU5muZvNFnQfXqceAHkf6vqhlzZ4Sq33DAiBr8-gEIubz-NCICZt8QePGeIjnggeQCwjwlg57vRnAUA
--- error_code: 401
--- response_body
{"message":"Failed to verify cwt"}
--- error_log
failed to verify cwt: Token has expired

=== TEST 18: verify request (token in header with bearer)
--- request
GET /hello
--- more_headers
cwt_auth: Bearer eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1GWXdFQVlIS29aSXpqMENBUVlGSzRFRUFBb0RRZ0FFaWJpcmx6eEtnZ0EzNWp1TUNtSmRhbUNDZ0hhOE9ZSkdcbk9HMFlIRzYxMUk5UDdrTEFBYlNqNGg0SFJHeUNSZnA0Ky9ndkxtcGU1Uis3UFV2bDNHU0NvZz09XG4tLS0tLUVORCBQVUJMSUMgS0VZLS0tLS0iXSwidHlwZSI6IkNXVCIsImNoYWluIjoiZXRoZXJldW0iLCJhbGciOiJzZWNwMjU2azEifQ.eyJ1c3IiOiJldGhlcmV1bSIsInRpbWUiOjE3MjA3Nzc4OTR9.MEYCIQDaQJfYwRxJiaZFWTU9XXsUOoy_7ZN2DBpEEqVsg1XyogIhALQAI0ifh7ZX3YQZx2LJ7-Ky5Zw35WjVQgqu0MpOAnqD
--- response_body
hello world

=== TEST 19: verify request (token in header without bearer)
--- request
GET /hello
--- more_headers
cwt_auth: eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1GWXdFQVlIS29aSXpqMENBUVlGSzRFRUFBb0RRZ0FFaWJpcmx6eEtnZ0EzNWp1TUNtSmRhbUNDZ0hhOE9ZSkdcbk9HMFlIRzYxMUk5UDdrTEFBYlNqNGg0SFJHeUNSZnA0Ky9ndkxtcGU1Uis3UFV2bDNHU0NvZz09XG4tLS0tLUVORCBQVUJMSUMgS0VZLS0tLS0iXSwidHlwZSI6IkNXVCIsImNoYWluIjoiZXRoZXJldW0iLCJhbGciOiJzZWNwMjU2azEifQ.eyJ1c3IiOiJldGhlcmV1bSIsInRpbWUiOjE3MjA3Nzc4OTR9.MEYCIQDaQJfYwRxJiaZFWTU9XXsUOoy_7ZN2DBpEEqVsg1XyogIhALQAI0ifh7ZX3YQZx2LJ7-Ky5Zw35WjVQgqu0MpOAnqD
--- response_body
hello world

=== TEST 20: verify request (token in cookie)
--- request
GET /hello
--- more_headers
Cookie: cwt_auth=eyJ4NWMiOlsiLS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS1cbk1GWXdFQVlIS29aSXpqMENBUVlGSzRFRUFBb0RRZ0FFaWJpcmx6eEtnZ0EzNWp1TUNtSmRhbUNDZ0hhOE9ZSkdcbk9HMFlIRzYxMUk5UDdrTEFBYlNqNGg0SFJHeUNSZnA0Ky9ndkxtcGU1Uis3UFV2bDNHU0NvZz09XG4tLS0tLUVORCBQVUJMSUMgS0VZLS0tLS0iXSwidHlwZSI6IkNXVCIsImNoYWluIjoiZXRoZXJldW0iLCJhbGciOiJzZWNwMjU2azEifQ.eyJ1c3IiOiJldGhlcmV1bSIsInRpbWUiOjE3MjA3Nzc4OTR9.MEYCIQDaQJfYwRxJiaZFWTU9XXsUOoy_7ZN2DBpEEqVsg1XyogIhALQAI0ifh7ZX3YQZx2LJ7-Ky5Zw35WjVQgqu0MpOAnqD
--- response_body
hello world

=== TEST 21: verify request (invalid token in header)
--- request
GET /hello
--- more_headers
cwt_auth: zZWNwMjU2azEifQ.eyJ1c3IiOiJldGhlcmV1bSIsInRpbWUiOjE3MjA3Nzc4OTR9.MEYCIQDaQJfYwRxJiaZFWTU9XXsUOoy_7ZN2DBpEEqVsg1XyogIhALQAI0ifh7ZX3YQZx2LJ7-Ky5Zw35WjVQgqu0MpOAnqD
--- error_code: 401
--- response_body
{"message":"cwt token invalid"}
--- error_log
cwt token invalid: invalid header: zZWNwMjU2azEifQ

=== TEST 22: verify request (invalid token in cookie)
--- request
GET /hello
--- more_headers
Cookie: cwt_auth=invalid-header.eyJ1c3IiOiJldGhlcmV1bSIsInRpbWUiOjE3MjA3Nzc4OTR9.MEYCIQDaQJfYwRxJiaZFWTU9XXsUOoy_7ZN2DBpEEqVsg1XyogIhALQAI0ifh7ZX3YQZx2LJ7-Ky5Zw35WjVQgqu0MpOAnqD
--- error_code: 401
--- response_body
{"message":"cwt token invalid"}
--- error_log
cwt token invalid: invalid header: invalid-header

=== TEST 23: delete 7 consumers
--- config
    location /t {
        content_by_lua_block {
            ngx.sleep(1)
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers/for_ripple_secp256k1', ngx.HTTP_DELETE)
            ngx.say("code: ", code < 300, ", body: ", body)

            code, body = t('/apisix/admin/consumers/for_ripple_ed25519', ngx.HTTP_DELETE)
            ngx.say("code: ", code < 300, ", body: ", body)

            code, body = t('/apisix/admin/consumers/for_jingtum_secp256k1', ngx.HTTP_DELETE)
            ngx.say("code: ", code < 300, ", body: ", body)

            code, body = t('/apisix/admin/consumers/for_jingtum_ed25519', ngx.HTTP_DELETE)
            ngx.say("code: ", code < 300, ", body: ", body)

            code, body = t('/apisix/admin/consumers/for_bitcoin', ngx.HTTP_DELETE)
            ngx.say("code: ", code < 300, ", body: ", body)

            code, body = t('/apisix/admin/consumers/for_ethereum', ngx.HTTP_DELETE)
            ngx.say("code: ", code < 300, ", body: ", body)

            code, body = t('/apisix/admin/consumers/expired_token', ngx.HTTP_DELETE)
            ngx.say("code: ", code < 300, ", body: ", body)
        }
    }
--- response_body
code: true, body: passed
code: true, body: passed
code: true, body: passed
code: true, body: passed
code: true, body: passed
code: true, body: passed
code: true, body: passed
