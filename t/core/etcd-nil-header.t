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

add_block_preprocessor(sub {
    my ($block) = @_;
    if (!defined $block->ignore_error_log) {
        $block->set_value("ignore_error_log", "");
    }
});

run_tests;

__DATA__

=== TEST 1: get_format returns error when body has no header field
--- config
    location /t {
        content_by_lua_block {
            local etcd_apisix = require("apisix.core.etcd")
            local res = {
                headers = {},
                body = {
                    kvs = {{key = "/test", value = "v"}},
                },
            }
            local ok, err = etcd_apisix.get_format(res, "/test", false)
            ngx.say("ok: ", ok ~= nil)
            ngx.say("err: ", err)
        }
    }
--- request
GET /t
--- response_body
ok: false
err: etcd response missing header.revision



=== TEST 2: get_format returns error when body is an empty table
--- config
    location /t {
        content_by_lua_block {
            local etcd_apisix = require("apisix.core.etcd")
            local res = {
                headers = {},
                body = {},
            }
            local ok, err = etcd_apisix.get_format(res, "/test", false)
            ngx.say("ok: ", ok ~= nil)
            ngx.say("err: ", err)
        }
    }
--- request
GET /t
--- response_body
ok: false
err: etcd response missing header.revision



=== TEST 3: get_format succeeds when header.revision is present
--- config
    location /t {
        content_by_lua_block {
            local etcd_apisix = require("apisix.core.etcd")
            local res = {
                headers = {},
                body = {
                    header = {revision = 100},
                    kvs = {{key = "/test", value = "v", create_revision = "1", mod_revision = "2"}},
                },
            }
            local ok, err = etcd_apisix.get_format(res, "/test", false)
            ngx.say("ok: ", ok ~= nil)
            ngx.say("err: ", err)
            ngx.say("revision: ", res.headers["X-Etcd-Index"])
        }
    }
--- request
GET /t
--- response_body
ok: true
err: nil
revision: 100
