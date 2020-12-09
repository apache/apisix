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

our $SkipReason;

BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}
use Test::Nginx::Socket::Lua $SkipReason ? (skip_all => $SkipReason) : ();
use t::APISIX 'no_plan';

master_on();
repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

run_tests;

__DATA__

=== TEST 1: sanity check
--- yaml_config
apisix:
    id: 123456
plugins:
    - server-info
plugin_attr:
    server-info:
        report_interval: 60
--- config
location /t {
    content_by_lua_block {
        ngx.sleep(2)
        local json_decode = require("cjson.safe").decode
        local core = require("apisix.core")
        local key = "/data_plane/server_info/" .. core.id.get()
        local res, err = core.etcd.get(key)
        if err ~= nil then
            ngx.status = 500
            ngx.say(err)
            return
        end

        local keys = {}
        local body = json_decode(res.body.node.value)
        for k in pairs(body) do
            keys[#keys + 1] = k
        end

        table.sort(keys)
        for i = 1, #keys do
            ngx.say(keys[i], ": ", body[keys[i]])
        end
    }
}
--- request
GET /t
--- response_body eval
qr{^boot_time: \d+
etcd_version: [\d\.]+
hostname: [a-zA-Z\-0-9\.]+
id: [a-zA-Z\-0-9]+
last_report_time: \d+
up_time: \d+
version: [\d\.]+
$}
--- no_error_log
[error]
--- error_log
timer created to report server info, interval: 60



=== TEST 2: verify the data integrity after reloading
--- yaml_config
apisix:
    id: 123456
plugins:
    - server-info
plugin_attr:
    server-info:
        report_interval: 60
--- config
location /t {
    content_by_lua_block {
        local json_decode = require("cjson.safe").decode
        local core = require("apisix.core")
        local key = "/data_plane/server_info/" .. core.id.get()
        local res, err = core.etcd.get(key)
        if err ~= nil then
            ngx.status = 500
            ngx.say(err)
            return
        end

        local keys = {}
        local body = json_decode(res.body.node.value)
        for k in pairs(body) do
            keys[#keys + 1] = k
        end

        if body.up_time >= 2 then
            ngx.say("integral")
        else
            ngx.say("reset")
        end
    }
}
--- request
GET /t
--- response_body
integral
--- no_error_log
[error]
--- error_log
timer created to report server info, interval: 60
