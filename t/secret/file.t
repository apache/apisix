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
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: validate schema
--- config
    location /t {
        content_by_lua_block {
            local test_case = {
                {},
                {base_path = 123},
                {base_path = "secrets"},
                {base_path = "/etc/secrets"},
            }
            local file = require("apisix.secret.file")
            local core = require("apisix.core")

            for _, conf in ipairs(test_case) do
                local ok, err = core.schema.check(file.schema, conf)
                ngx.say(ok and "done" or err)
            end
        }
    }
--- response_body
property "base_path" is required
property "base_path" validation failed: wrong type: expected string, got number
property "base_path" validation failed: failed to match pattern "^/" with "secrets"
done



=== TEST 2: reject keys that are empty, absolute or leave base_path
--- config
    location /t {
        content_by_lua_block {
            local file = require("apisix.secret.file")
            local conf = {base_path = ngx.config.prefix() .. "conf/secrets"}

            for _, key in ipairs({"", "/etc/passwd", "..", "../apisix.yaml",
                                  "db/../../apisix.yaml", "db/.."}) do
                local value, err = file.get(conf, key)
                ngx.say(value or err)
            end
        }
    }
--- response_body
can't find main key, key: 
can't find main key, key: /etc/passwd
key must not contain '..' segments, key: ..
key must not contain '..' segments, key: ../apisix.yaml
key must not contain '..' segments, key: db/../../apisix.yaml
key must not contain '..' segments, key: db/..



=== TEST 3: read secret files
--- user_files
>>> ../conf/secrets/password
s3cr3t
>>> ../conf/secrets/db/user
admin
>>> ../conf/secrets/..data
not-a-traversal
--- config
    location /t {
        content_by_lua_block {
            local file = require("apisix.secret.file")
            local prefix = ngx.config.prefix()

            for _, base_path in ipairs({prefix .. "conf/secrets", prefix .. "conf/secrets/"}) do
                local conf = {base_path = base_path}
                for _, key in ipairs({"password", "db/user", "..data"}) do
                    local value, err = file.get(conf, key)
                    ngx.say(key, ": ", value or err)
                end
            end

            local value, err = file.get({base_path = prefix .. "conf/secrets"}, "missing")
            ngx.say("missing: ", value or (err:find("No such file", 1, true) and "no such file" or err))
        }
    }
--- response_body
password: s3cr3t
db/user: admin
..data: not-a-traversal
password: s3cr3t
db/user: admin
..data: not-a-traversal
missing: no such file



=== TEST 4: only one trailing newline is removed
--- config
    location /t {
        content_by_lua_block {
            local file = require("apisix.secret.file")
            local dir = ngx.config.prefix() .. "conf/"
            local cases = {
                {"no-newline", "abc"},
                {"lf", "abc\n"},
                {"crlf", "abc\r\n"},
                {"two-lf", "abc\n\n"},
                {"multi-line", "line1\nline2\n"},
            }
            for _, c in ipairs(cases) do
                local f = assert(io.open(dir .. c[1], "w"))
                f:write(c[2])
                f:close()
                local value = file.get({base_path = dir}, c[1])
                ngx.say(c[1], ": ", ngx.encode_base64(value))
            end
        }
    }
--- response_body
no-newline: YWJj
lf: YWJj
crlf: YWJj
two-lf: YWJjCg==
multi-line: bGluZTEKbGluZTI=



=== TEST 5: fetch a secret by uri
--- user_files
>>> ../conf/secrets/jack-key
jack-key-value
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/secrets/file/mysecret',
                ngx.HTTP_PUT,
                core.json.encode({base_path = ngx.config.prefix() .. "conf/secrets"})
            )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            local secret = require("apisix.secret")
            local value, err = secret.fetch_by_uri("$secret://file/mysecret/jack-key")
            ngx.say("secret value: ", value or err)

            value, err = secret.fetch_by_uri("$secret://file/mysecret/../jack-key")
            ngx.say(value or err)

            code, body = t('/apisix/admin/secrets/file/mysecret', ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end
        }
    }
--- response_body
secret value: jack-key-value
key must not contain '..' segments, key: ../jack-key



=== TEST 6: use a file secret in key-auth
--- user_files
>>> ../conf/secrets/jack-key
jack-key-value
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/secrets/file/mysecret',
                ngx.HTTP_PUT,
                core.json.encode({base_path = ngx.config.prefix() .. "conf/secrets"})
            )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                            "key": "$secret://file/mysecret/jack-key"
                        }
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "plugins": {
                        "key-auth": {}
                    },
                    "upstream": {
                        "nodes": {"127.0.0.1:1980": 1},
                        "type": "roundrobin"
                    }
                }]]
            )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end
            ngx.say("passed")
        }
    }
--- response_body
passed



=== TEST 7: request with the key from the file
--- user_files
>>> ../conf/secrets/jack-key
jack-key-value
--- request
GET /hello
--- more_headers
apikey: jack-key-value
--- response_body
hello world
