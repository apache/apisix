use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

run_tests;

__DATA__

=== TEST 1: add consumer with csrf plugin (data encryption enabled)
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json = require("toolkit.json")
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                            "key": "key-a"
                        },
                        "csrf": {
                            "key": "userkey",
                            "expires": 1000000000
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

            -- verify csrf key is decrypted in admin API
            local code, message, res = t('/apisix/admin/consumers/jack',
                ngx.HTTP_GET
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end
            local consumer = json.decode(res)
            ngx.say(consumer.value.plugins["csrf"].key)

            -- verify csrf key is encrypted in etcd
            local etcd = require("apisix.core.etcd")
            local res = assert(etcd.get('/consumers/jack'))
            ngx.say(res.body.node.value.plugins["csrf"].key)
        }
    }
--- request
GET /t
--- response_body
userkey
mt39FazQccyMqt4ctoRV7w==
--- no_error_log
[error]



=== TEST 2: add route
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "key-auth": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
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



=== TEST 3: invalid request - no csrf token
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- request
POST /hello
--- more_headers
apikey: key-a
--- error_code: 401
--- response_body
{"error_msg":"no csrf token in headers"}



=== TEST 4: valid request - with csrf token
--- yaml_config
apisix:
    data_encryption:
        enable_encrypt_fields: true
        keyring:
            - edd1c9f0985e76a2
--- request
POST /hello
--- more_headers
apikey: key-a
apisix-csrf-token: eyJyYW5kb20iOjAuNDI5ODYzMTk3MTYxMzksInNpZ24iOiI0ODRlMDY4NTkxMWQ5NmJhMDc5YzQ1ZGI0OTE2NmZkYjQ0ODhjODVkNWQ0NmE1Y2FhM2UwMmFhZDliNjE5OTQ2IiwiZXhwaXJlcyI6MjY0MzExOTYyNH0=
Cookie: apisix-csrf-token=eyJyYW5kb20iOjAuNDI5ODYzMTk3MTYxMzksInNpZ24iOiI0ODRlMDY4NTkxMWQ5NmJhMDc5YzQ1ZGI0OTE2NmZkYjQ0ODhjODVkNWQ0NmE1Y2FhM2UwMmFhZDliNjE5OTQ2IiwiZXhwaXJlcyI6MjY0MzExOTYyNH0=
--- response_body
hello world
--- no_error_log
[error]
