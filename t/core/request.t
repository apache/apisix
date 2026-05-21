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

=== TEST 1: get_ip
--- config
    location /t {
        real_ip_header X-Real-IP;

        set_real_ip_from 0.0.0.0/0;
        set_real_ip_from ::/0;
        set_real_ip_from unix:;

        access_by_lua_block {
            local core = require("apisix.core")
            local ngx_ctx = ngx.ctx
            local api_ctx = ngx_ctx.api_ctx
            if api_ctx == nil then
                api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
                ngx_ctx.api_ctx = api_ctx
            end

            core.ctx.set_vars_meta(api_ctx)
        }
        content_by_lua_block {
            local core = require("apisix.core")
            local ip = core.request.get_ip(ngx.ctx.api_ctx)
            ngx.say(ip)
        }
    }
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
127.0.0.1



=== TEST 2: get_ip
--- config
    location /t {
        real_ip_header X-Real-IP;

        set_real_ip_from 0.0.0.0/0;
        set_real_ip_from ::/0;
        set_real_ip_from unix:;

        access_by_lua_block {
            local core = require("apisix.core")
            local ngx_ctx = ngx.ctx
            local api_ctx = ngx_ctx.api_ctx
            if api_ctx == nil then
                api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
                ngx_ctx.api_ctx = api_ctx
            end

            core.ctx.set_vars_meta(api_ctx)
        }
        content_by_lua_block {
            local core = require("apisix.core")
            local ip = core.request.get_ip(ngx.ctx.api_ctx)
            ngx.say(ip)
        }
    }
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
127.0.0.1



=== TEST 3: get_ip and X-Forwarded-For
--- config
    location /t {
        real_ip_header X-Forwarded-For;

        set_real_ip_from 0.0.0.0/0;
        set_real_ip_from ::/0;
        set_real_ip_from unix:;

        access_by_lua_block {
            local core = require("apisix.core")
            local ngx_ctx = ngx.ctx
            local api_ctx = ngx_ctx.api_ctx
            if api_ctx == nil then
                api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
                ngx_ctx.api_ctx = api_ctx
            end

            core.ctx.set_vars_meta(api_ctx)
        }
        content_by_lua_block {
            local core = require("apisix.core")
            local ip = core.request.get_ip(ngx.ctx.api_ctx)
            ngx.say(ip)
        }
    }
--- more_headers
X-Forwarded-For: 10.0.0.1
--- response_body
127.0.0.1



=== TEST 4: get_remote_client_ip
--- config
    location /t {
        real_ip_header X-Real-IP;

        set_real_ip_from 0.0.0.0/0;
        set_real_ip_from ::/0;
        set_real_ip_from unix:;

        access_by_lua_block {
            local core = require("apisix.core")
            local ngx_ctx = ngx.ctx
            local api_ctx = ngx_ctx.api_ctx
            if api_ctx == nil then
                api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
                ngx_ctx.api_ctx = api_ctx
            end

            core.ctx.set_vars_meta(api_ctx)
        }
        content_by_lua_block {
            local core = require("apisix.core")
            local ip = core.request.get_remote_client_ip(ngx.ctx.api_ctx)
            ngx.say(ip)
        }
    }
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
10.0.0.1



=== TEST 5: get_remote_client_ip and X-Forwarded-For
--- config
    location /t {
        real_ip_header X-Forwarded-For;
        set_real_ip_from 0.0.0.0/0;
        set_real_ip_from ::/0;
        set_real_ip_from unix:;

        access_by_lua_block {
            local core = require("apisix.core")
            local ngx_ctx = ngx.ctx
            local api_ctx = ngx_ctx.api_ctx
            if api_ctx == nil then
                api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
                ngx_ctx.api_ctx = api_ctx
            end

            core.ctx.set_vars_meta(api_ctx)
        }
        content_by_lua_block {
            local core = require("apisix.core")
            local ip = core.request.get_remote_client_ip(ngx.ctx.api_ctx)
            ngx.say(ip)
        }
    }
--- more_headers
X-Forwarded-For: 10.0.0.1
--- response_body
10.0.0.1



=== TEST 6: get_host
--- config
    location /t {
        real_ip_header X-Real-IP;

        set_real_ip_from 0.0.0.0/0;
        set_real_ip_from ::/0;
        set_real_ip_from unix:;

        access_by_lua_block {
            local core = require("apisix.core")
            local ngx_ctx = ngx.ctx
            local api_ctx = ngx_ctx.api_ctx
            if api_ctx == nil then
                api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
                ngx_ctx.api_ctx = api_ctx
            end

            core.ctx.set_vars_meta(api_ctx)
        }
        content_by_lua_block {
            local core = require("apisix.core")
            local host = core.request.get_host(ngx.ctx.api_ctx)
            ngx.say(host)
        }
    }
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
localhost



=== TEST 7: get_scheme
--- config
    location /t {
        real_ip_header X-Real-IP;

        set_real_ip_from 0.0.0.0/0;
        set_real_ip_from ::/0;
        set_real_ip_from unix:;

        access_by_lua_block {
            local core = require("apisix.core")
            local ngx_ctx = ngx.ctx
            local api_ctx = ngx_ctx.api_ctx
            if api_ctx == nil then
                api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
                ngx_ctx.api_ctx = api_ctx
            end

            core.ctx.set_vars_meta(api_ctx)
        }
        content_by_lua_block {
            local core = require("apisix.core")
            local scheme = core.request.get_scheme(ngx.ctx.api_ctx)
            ngx.say(scheme)
        }
    }
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
http



=== TEST 8: get_port
--- config
    location /t {
        real_ip_header X-Real-IP;

        set_real_ip_from 0.0.0.0/0;
        set_real_ip_from ::/0;
        set_real_ip_from unix:;

        access_by_lua_block {
            local core = require("apisix.core")
            local ngx_ctx = ngx.ctx
            local api_ctx = ngx_ctx.api_ctx
            if api_ctx == nil then
                api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
                ngx_ctx.api_ctx = api_ctx
            end

            core.ctx.set_vars_meta(api_ctx)
        }
        content_by_lua_block {
            local core = require("apisix.core")
            local port = core.request.get_port(ngx.ctx.api_ctx)
            ngx.say(port)
        }
    }
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
1984



=== TEST 9: get_http_version
--- config
    location /t {
        real_ip_header X-Real-IP;

        set_real_ip_from 0.0.0.0/0;
        set_real_ip_from ::/0;
        set_real_ip_from unix:;

        access_by_lua_block {
            local core = require("apisix.core")
            local ngx_ctx = ngx.ctx
            local api_ctx = ngx_ctx.api_ctx
            if api_ctx == nil then
                api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
                ngx_ctx.api_ctx = api_ctx
            end

            core.ctx.set_vars_meta(api_ctx)
        }
        content_by_lua_block {
            local core = require("apisix.core")
            local http_version = core.request.get_http_version()
            ngx.say(http_version)
        }
    }
--- more_headers
X-Real-IP: 10.0.0.1
--- response_body
1.1



=== TEST 10: set header
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.ctx.api_ctx = {}
            local h = core.request.header(nil, "Test")
            local ctx = ngx.ctx.api_ctx
            core.request.set_header(ctx, "Test", "t")
            local h2 = core.request.header(ctx, "Test")
            ngx.say(h)
            ngx.say(h2)
        }
    }
--- response_body
nil
t



=== TEST 11: get_post_args
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local ngx_ctx = ngx.ctx
            local api_ctx = ngx_ctx.api_ctx
            if api_ctx == nil then
                api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
                ngx_ctx.api_ctx = api_ctx
            end

            core.ctx.set_vars_meta(api_ctx)

            local args = core.request.get_post_args(ngx.ctx.api_ctx)
            ngx.say(args["c"])
            ngx.say(args["v"])
        }
    }
--- request
POST /t
c=z_z&v=x%20x
--- response_body
z_z
x x



=== TEST 12: get_post_args when the body is stored in temp file
--- config
    location /t {
        client_body_in_file_only clean;
        content_by_lua_block {
            local core = require("apisix.core")
            local ngx_ctx = ngx.ctx
            local api_ctx = ngx_ctx.api_ctx
            if api_ctx == nil then
                api_ctx = core.tablepool.fetch("api_ctx", 0, 32)
                ngx_ctx.api_ctx = api_ctx
            end

            core.ctx.set_vars_meta(api_ctx)

            local args = core.request.get_post_args(ngx.ctx.api_ctx)
            ngx.say(args["c"])
        }
    }
--- request
POST /t
c=z_z&v=x%20x
--- response_body
nil
--- error_log
the post form is too large: request body in temp file not supported



=== TEST 13: get_method
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.say(core.request.get_method())
        }
    }
--- request
POST /t
--- response_body
POST



=== TEST 14: add header
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.ctx.api_ctx = {}
            local ctx = ngx.ctx.api_ctx
            local json = require("toolkit.json")
            core.request.add_header(ctx, "test_header", "test")
            local h = core.request.header(ctx, "test_header")
            ngx.say(h)
            core.request.add_header(ctx, "test_header", "t2")
            local h2 = core.request.headers(ctx)["test_header"]
            ngx.say(json.encode(h2))
            core.request.add_header(ctx, "test_header", "t3")
            local h3 = core.request.headers(ctx)["test_header"]
            ngx.say(json.encode(h3))
        }
    }
--- response_body
test
["test","t2"]
["test","t2","t3"]



=== TEST 15: call add_header with deprecated way
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.ctx.api_ctx = {}
            local ctx = ngx.ctx.api_ctx
            core.request.add_header("test_header", "test")
            local h = core.request.header(ctx, "test_header")
            ngx.say(h)
        }
    }
--- response_body
test
--- error_log
DEPRECATED: use add_header(ctx, header_name, header_value) instead



=== TEST 16: after setting the header, ctx.var can still access the correct value
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.ctx.api_ctx = {}
            local ctx = ngx.ctx.api_ctx
            core.ctx.set_vars_meta(ctx)

            ctx.var.http_server = "ngx"
            ngx.say(ctx.var.http_server)

            core.request.set_header(ctx, "server",  "test")
            ngx.say(ctx.var.http_server)

            -- case-insensitive
            core.request.set_header(ctx, "Server",  "apisix")
            ngx.say(ctx.var.http_server)
        }
    }
--- response_body
ngx
test
apisix



=== TEST 17: get_json_request_body_table caches result and re-decodes after set_body_data
--- yaml_config
apisix:
  request_body_json_lib: cjson
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local request_json = require("apisix.core.request_json")

            ngx.ctx.api_ctx = {}

            local decode_count = 0
            local orig_decode = request_json.decode
            request_json.decode = function(str)
                decode_count = decode_count + 1
                return orig_decode(str)
            end

            -- first call: populates cache
            local t1 = core.request.get_json_request_body_table()
            -- second and third calls: hit cache, no extra decode
            local t2 = core.request.get_json_request_body_table()
            local t3 = core.request.get_json_request_body_table()

            ngx.say("model: ", t1 and t1.model)
            ngx.say("same table: ", t1 == t2 and t2 == t3)
            ngx.say("decode_count: ", decode_count)

            -- invalidate cache by replacing body
            ngx.req.set_body_data('{"model":"claude"}')

            -- cache cleared, must re-decode
            local t4 = core.request.get_json_request_body_table()

            request_json.decode = orig_decode

            ngx.say("after set_body model: ", t4 and t4.model)
            ngx.say("decode_count: ", decode_count)
        }
    }
--- request
POST /t
{"model":"gpt-4","messages":[{"role":"user","content":"hi"}]}
--- more_headers
Content-Type: application/json
--- response_body
model: gpt-4
same table: true
decode_count: 1
after set_body model: claude
decode_count: 2



=== TEST 18: request_json selects configured JSON library
--- config
    location /t {
        content_by_lua_block {
            local config_local = require("apisix.core.config_local")
            local orig_local_conf = config_local.local_conf
            local orig_qjson = package.loaded["qjson"]
            local orig_preload_qjson = package.preload["qjson"]
            local orig_simdjson = package.loaded["resty.simdjson"]
            local orig_preload_simdjson = package.preload["resty.simdjson"]
            local orig_request_json = package.loaded["apisix.core.request_json"]

            package.loaded["qjson"] = {
                decode = function()
                    return {lib = "qjson", lazy = true}
                end,
                materialize = function(data)
                    data.lazy = false
                    return data
                end,
                encode = function(data)
                    return "qjson:" .. data.lib
                end,
            }

            package.loaded["resty.simdjson"] = {
                new = function()
                    return {
                        decode = function()
                            return {lib = "simdjson"}
                        end,
                    }
                end,
            }

            local function load_with(lib)
                config_local.local_conf = function()
                    return {apisix = {request_body_json_lib = lib}}
                end
                package.loaded["apisix.core.request_json"] = nil
                return require("apisix.core.request_json")
            end

            local request_json = load_with("qjson")
            local decoded = request_json.decode("{}")
            local encoded = request_json.encode({lib = "body"})
            ngx.say("qjson decode: ", decoded.lib)
            ngx.say("qjson materialized: ", not decoded.lazy)
            ngx.say("qjson encode: ", encoded)

            request_json = load_with("simdjson")
            decoded = request_json.decode("{}")
            encoded = request_json.encode({lib = "body"})
            ngx.say("simdjson decode: ", decoded.lib)
            ngx.say("simdjson encode: ", encoded)

            request_json = load_with("cjson")
            decoded = request_json.decode('{"lib":"cjson"}')
            encoded = request_json.encode({lib = "body"})
            ngx.say("cjson decode: ", decoded.lib)
            ngx.say("cjson encode: ", encoded)

            config_local.local_conf = orig_local_conf
            package.loaded["apisix.core.request_json"] = orig_request_json
            package.loaded["qjson"] = orig_qjson
            package.preload["qjson"] = orig_preload_qjson
            package.loaded["resty.simdjson"] = orig_simdjson
            package.preload["resty.simdjson"] = orig_preload_simdjson
        }
    }
--- response_body
qjson decode: qjson
qjson materialized: true
qjson encode: qjson:body
simdjson decode: simdjson
simdjson encode: {"lib":"body"}
cjson decode: cjson
cjson encode: {"lib":"body"}



=== TEST 19: qjson decode and encode errors are returned
--- yaml_config
apisix:
  request_body_json_lib: qjson
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local request_json = require("apisix.core.request_json")

            ngx.ctx.api_ctx = {}

            local body, body_err = core.request.get_json_request_body_table()
            ngx.say("body nil: ", body == nil)
            ngx.say("body error: ", body_err and body_err.message and
                    body_err.message:find("could not parse JSON request body:", 1, true) == 1)

            local decoded, decode_err = request_json.decode("{")
            ngx.say("decode nil: ", decoded == nil)
            ngx.say("decode error: ", type(decode_err) == "string" and #decode_err > 0)

            local encoded, encode_err = request_json.encode({bad = function() end})
            ngx.say("encode nil: ", encoded == nil)
            ngx.say("encode error: ", type(encode_err) == "string" and #encode_err > 0)
        }
    }
--- request
POST /t
{
--- more_headers
Content-Type: application/json
--- response_body
body nil: true
body error: true
decode nil: true
decode error: true
encode nil: true
encode error: true
--- no_error_log
[error]



=== TEST 20: simdjson preserves empty arrays for cjson encoding
--- yaml_config
apisix:
  request_body_json_lib: simdjson
--- config
    location /t {
        content_by_lua_block {
            local core_json = require("apisix.core.json")
            local request_json = require("apisix.core.request_json")

            local decoded = request_json.decode('{"messages":[],"metadata":{"tags":[]}}')
            local encoded = request_json.encode(decoded)
            local round_trip = core_json.decode(encoded)

            ngx.say("messages array: ", getmetatable(round_trip.messages) == core_json.array_mt)
            ngx.say("tags array: ", getmetatable(round_trip.metadata.tags) == core_json.array_mt)
        }
    }
--- response_body
messages array: true
tags array: true



=== TEST 21: ai transport encoders use request_json
--- config
    location /t {
        content_by_lua_block {
            local request_json = require("apisix.core.request_json")
            local orig_encode = request_json.encode
            local orig_request_json = package.loaded["apisix.core.request_json"]
            local orig_http = package.loaded["resty.http"]
            local orig_aws_config = package.loaded["resty.aws.config"]
            local orig_aws = package.loaded["resty.aws"]
            local orig_sign = package.loaded["resty.aws.request.sign"]
            local orig_transport = package.loaded["apisix.plugins.ai-transport.http"]
            local orig_auth_aws = package.loaded["apisix.plugins.ai-transport.auth-aws"]
            request_json.encode = function()
                return "encoded-by-request-json"
            end

            package.loaded["resty.http"] = {
                new = function()
                    return {
                        set_timeout = function() end,
                        connect = function() return true end,
                        request = function(_, params)
                            ngx.say("http body: ", params.body)
                            return {headers = {}, status = 200}
                        end,
                        close = function() end,
                    }
                end,
            }

            package.loaded["apisix.plugins.ai-transport.http"] = nil
            local transport = require("apisix.plugins.ai-transport.http")
            local res, err = transport.request({
                host = "127.0.0.1",
                port = 80,
                path = "/",
                body = {model = "test"},
            }, 1000)
            if not res then
                ngx.say(err)
            end

            package.loaded["resty.aws.config"] = {}
            package.loaded["resty.aws"] = function()
                return {
                    Credentials = function(_, opts)
                        return opts
                    end,
                }
            end
            package.loaded["resty.aws.request.sign"] = function(_, req)
                ngx.say("aws body: ", req.body)
                return {headers = {Authorization = "signed"}}
            end

            package.loaded["apisix.plugins.ai-transport.auth-aws"] = nil
            local auth_aws = require("apisix.plugins.ai-transport.auth-aws")
            local sign_err = auth_aws.sign_request({
                method = "POST",
                host = "bedrock-runtime.us-east-1.amazonaws.com",
                port = 443,
                path = "/model/test/converse",
                headers = {},
                body = {model = "test"},
            }, {
                access_key_id = "ak",
                secret_access_key = "sk",
            }, "us-east-1")
            if sign_err then
                ngx.say(sign_err)
            end

            request_json.encode = orig_encode
            package.loaded["resty.http"] = orig_http
            package.loaded["resty.aws.config"] = orig_aws_config
            package.loaded["resty.aws"] = orig_aws
            package.loaded["resty.aws.request.sign"] = orig_sign
            package.loaded["apisix.core.request_json"] = orig_request_json
            package.loaded["apisix.plugins.ai-transport.http"] = orig_transport
            package.loaded["apisix.plugins.ai-transport.auth-aws"] = orig_auth_aws
        }
    }
--- response_body
http body: encoded-by-request-json
aws body: encoded-by-request-json
