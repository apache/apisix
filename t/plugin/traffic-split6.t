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
add_block_preprocessor(sub{
	 my ($block) = @_;
	if (!$block->extra_init_by_lua) {
        my $extra_init_by_lua = <<_EOC_;
-- bypass schema validation
local plugin = require("apisix.plugins.traffic-split")
plugin.check_schema = function(schema)
	return true
end
_EOC_

        $block->set_value("extra_init_by_lua", $extra_init_by_lua);
    }
	$block;
});

run_tests;

__DATA__

=== TEST 1: even when schema validation is bypassed, upstream "abc" will be assigned "plugin#upstream#is#empty" instead of panic
--- config
    location /t {
        content_by_lua_block {
           local json = require("toolkit.json")
            local t = require("lib.test_admin").test
            local data = {
                uri = "/server_port",
                plugins = {
                    ["traffic-split"] = {
                        rules = { {
                        weighted_upstreams = { {
                            upstream = "abc",
                        }, {
                            weight = 1
                        } }
                        } }
                    }
                },
                upstream = {
                    type = "roundrobin",
                    nodes = {
                        ["127.0.0.1:1980"] = 1
                    }
                }
            }
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                json.encode(data)
            )

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done



=== TEST 2: there should be no panic
--- request
GET /server_port
--- response_body eval
1980
