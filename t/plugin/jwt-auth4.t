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
    $ENV{VAULT_TOKEN} = "root";
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
        if (!$block->response_body) {
            $block->set_value("response_body", "passed\n");
        }
    }
});

run_tests;

__DATA__

=== TEST 1: verify the real_payload's value (key & exp) is not overridden by malicious payload
--- config
    location /t {
        content_by_lua_block {
	    local core = require("apisix.core")
            local t = require("lib.test_admin").test

            -- prepare consumer
	    local csm_code, csm_body = t('/apisix/admin/consumers',
	        ngx.HTTP_PUT,
		[[{
		    "username": "jack",
		    "plugins": {
		        "jwt-auth": {
			    "key": "user-key",
			    "secret": "my-secret-key"
                        }
                    }
		}]]
	    ) 

            if csm_code >= 300 then
                ngx.status = csm_code
		ngx.say(csm_body)
	        return
	    end

	    -- prepare sign api
            local rot_code, rot_body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "public-api": {}
                    },
                    "uri": "/apisix/plugin/jwt/sign"
                }]]
            )

	    if rot_code >= 300 then
                ngx.status = rot_code
		ngx.say(rot_body)
	        return
	    end

            -- generate jws
	    local code, err, sign = t('/apisix/plugin/jwt/sign?key=user-key&payload={"key":"letmein","exp":1234567890}',
	        ngx.HTTP_GET
	    )

	    if code > 200 then
                ngx.status = code
		ngx.say(err)
		return
	    end

	    -- get payload section from jws
	    local payload = string.match(sign,"^.+%.(.+)%..+$")

	    if not payload then
	        ngx.say("sign-failed")
		return
	    end

	    -- check payload value
	    local res = core.json.decode(ngx.decode_base64(payload))

	    if res.key == 'user-key' and res.exp ~= 1234567890 then
	       ngx.say("safe-jws")
	       return
	    end 

            ngx.say("fake-jws")
        }
    }
--- response_body
safe-jws

