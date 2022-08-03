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

log_level('debug');
repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests;

__DATA__

=== TEST 1: schema check
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.tencent-cloud-cls")
            local ok, err = plugin.check_schema({
                cls_host = "ap-guangzhou.cls.tencentyun.com",
                cls_topic = "143b5d70-139b-4aec-b54e-bb97756916de",
                secret_id = "secret_id",
                secret_key = "secret_key",
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: cls config missing
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.tencent-cloud-cls")
            local ok, err = plugin.check_schema({
                cls_host = "ap-guangzhou.cls.tencentyun.com",
                cls_topic = "143b5d70-139b-4aec-b54e-bb97756916de",
                secret_id = "secret_id",
            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
property "secret_key" is required
done



=== TEST 3: add plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "tencent-cloud-cls": {
                                "cls_host": "ap-guangzhou.cls.tencentyun.com",
                                "cls_topic": "143b5d70-139b-4aec-b54e-bb97756916de",
                                "secret_id": "secret_id",
                                "secret_key": "secret_key"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1982": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/opentracing"
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



=== TEST 4: access local server
--- request
GET /opentracing
--- response_body
opentracing
--- error_log
Batch Processor[tencent-cloud-cls] successfully processed the entries
--- wait: 0.5
