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

    if (!defined $block->no_error_log) {
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
