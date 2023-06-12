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
    $ENV{TEST_ENV_VAR} = "test-value";
    $ENV{TEST_ENV_SUB_VAR} = '{"main":"main_value","sub":"sub_value"}';
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();

run_tests;

__DATA__

=== TEST 1: sanity: start with $env://
--- config
    location /t {
        content_by_lua_block {
            local env = require("apisix.core.env")
            local value = env.fetch_by_uri("$env://TEST_ENV_VAR")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
test-value



=== TEST 2: sanity: start with $ENV://
--- config
    location /t {
        content_by_lua_block {
            local env = require("apisix.core.env")
            local value = env.fetch_by_uri("$ENV://TEST_ENV_VAR")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
test-value



=== TEST 3: env var case sensitive
--- config
    location /t {
        content_by_lua_block {
            local env = require("apisix.core.env")
            local value = env.fetch_by_uri("$ENV://test_env_var")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
nil



=== TEST 4: wrong format: wrong type
--- config
    location /t {
        content_by_lua_block {
            local env = require("apisix.core.env")
            local _, err = env.fetch_by_uri(1)
            ngx.say(err)

            local _, err = env.fetch_by_uri(true)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
error env_uri type: number
error env_uri type: boolean



=== TEST 5: wrong format: wrong prefix
--- config
    location /t {
        content_by_lua_block {
            local env = require("apisix.core.env")
            local _, err = env.fetch_by_uri("env://")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
error env_uri prefix: env://



=== TEST 6: sub value
--- config
    location /t {
        content_by_lua_block {
            local env = require("apisix.core.env")
            local value = env.fetch_by_uri("$ENV://TEST_ENV_SUB_VAR/main")
            ngx.say(value)
            local value = env.fetch_by_uri("$ENV://TEST_ENV_SUB_VAR/sub")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
main_value
sub_value



=== TEST 7: wrong sub value: error json
--- config
    location /t {
        content_by_lua_block {
            local env = require("apisix.core.env")
            local _, err = env.fetch_by_uri("$ENV://TEST_ENV_VAR/main")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
decode failed, err: Expected value but found invalid token at character 1, value: test-value



=== TEST 8: wrong sub value: not exits
--- config
    location /t {
        content_by_lua_block {
            local env = require("apisix.core.env")
            local value = env.fetch_by_uri("$ENV://TEST_ENV_VAR/no")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
nil



=== TEST 9: use nginx env
--- main_config
env ngx_env=apisix-nice;
--- config
    location /t {
        content_by_lua_block {
            local env = require("apisix.core.env")
            local value = env.fetch_by_uri("$ENV://ngx_env")
            ngx.say(value)
        }
    }
--- request
GET /t
--- response_body
apisix-nice
