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

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!defined $block->error_log && !defined $block->no_error_log) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests;

__DATA__

=== TEST 1: flatten send args
--- extra_init_by_lua
local sock = ngx.socket.tcp()
getmetatable(sock.sock).__index.send = function (_, data)
    ngx.log(ngx.WARN, data)
    return #data
end
sock:send({1, "a", {1, "b", true}})
sock:send(1, "a", {1, "b", false})
--- config
    location /t {
        return 200;
    }
--- grep_error_log eval
qr/send\(\): \S+/
--- grep_error_log_out
send(): 1a1btrue
send(): 1a1bfalse



=== TEST 2: sslhandshake options
--- extra_init_by_lua
local sock = ngx.socket.tcp()
sock:settimeout(1)
local ok, err = sock:connect("0.0.0.0", 12379)
if not ok then
    ngx.log(ngx.ERR, "failed to connect: ", err)
    return
end

local sess, err = sock:sslhandshake(true, "test.com", true, true)
if not sess then
    ngx.log(ngx.ERR, "failed to do SSL handshake: ", err)
end

local sock = ngx.socket.tcp()
local ok, err = sock:connect("0.0.0.0", 12379)
if not ok then
    ngx.log(ngx.ERR, "failed to connect: ", err)
    return
end
local sess, err = sock:sslhandshake(true, "test.com", nil, true)
if not sess then
    ngx.log(ngx.ERR, "failed to do SSL handshake: ", err)
end

sock:setkeepalive()
--- config
    location /t {
        return 200;
    }
--- grep_error_log eval
qr/failed to do SSL handshake/
--- grep_error_log_out
failed to do SSL handshake
--- error_log
reused_session is not supported yet
send_status_req is not supported yet



=== TEST 3: unix socket
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- extra_init_worker_by_lua
local sock = ngx.socket.tcp()
sock:settimeout(1)
local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
if not ok then
    ngx.log(ngx.ERR, "failed to connect: ", err)
    return
end

local ok, err = sock:receive()
if not ok then
    ngx.log(ngx.ERR, "failed to read: ", err)
    return
end
--- config
    location /t {
        return 200;
    }
--- error_log
failed to read: timeout



=== TEST 4: resolve host by ourselves
--- yaml_config
apisix:
  node_listen: 1984
  enable_resolv_search_opt: true
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local httpc = http.new()
            local res, err = httpc:request_uri("http://apisix")
            if not res then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say(res.status)
        }
    }
--- request
GET /t
--- response_body
301
