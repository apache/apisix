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
use Digest;

repeat_each(1);
no_long_string();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

our $tempfile_body = 'a' x (1024*1024*11);
our $memory_body = 'b' x 1024;
our $tempfile_body_md5 = Digest->new("MD5")->add($tempfile_body)->hexdigest;
our $memory_body_md5 = Digest->new("MD5")->add($memory_body)->hexdigest;

run_tests();

__DATA__

=== TEST 1: setup route with plugin
--- config
    location /t {
        content_by_lua_block {
            local data = {
                {
                    url = "/apisix/admin/upstreams/u1",
                    data = [[{
                        "nodes": {
                            "127.0.0.1:1984": 1
                        },
                        "type": "roundrobin"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/auth",
                    data = {
                        plugins = {
                            ["serverless-pre-function"] = {
                                phase = "rewrite",
                                functions = {
                                    [[
				    return function(conf, ctx)
                                        local core = require("apisix.core")
                                        if core.request.get_method() == "POST" then
                                            if core.request.header(ctx, "Authorization") == "read-whole-client-body" then
					        local body = core.request.get_body()
						local content_length = tonumber(ngx.var.content_length)
						if content_length > 0 then
						    assert(#body == content_length)
						end
                                                core.response.exit(200)
                                            end
                                            if core.request.header(ctx, "Authorization") == "simulate-partially-read-client-body" then
					        ngx.sleep(1)
                                                ngx.exit(ngx.ERROR)
                                            end
                                        end
                                    end
				    ]]
                                }
                            }
                        },
                        uri = "/auth"
                    }
                },
                {
                    url = "/apisix/admin/routes/echo",
                    data = {
                        plugins = {
                            ["serverless-pre-function"] = {
                                phase = "rewrite",
                                functions = {
                                    [[
				    return function(conf, ctx)
                                        local core = require("apisix.core")
					local resty_md5 = require("resty.md5")
					local resty_str = require("resty.string")
					local body = core.request.get_body()
					assert(#body == tonumber(ngx.var.content_length))
					local md5 = resty_md5:new()
					md5:update(body)
					local digest = md5:final()
					local body_md5 = resty_str.to_hex(digest)
                                        core.response.exit(200, body_md5)
                                    end
				    ]]
                                }
                            }
                        },
                        uri = "/echo"
                    }
                },
                {
                    url = "/apisix/admin/routes/1",
                    data = [[{
                        "plugins": {
                        "forward-auth": {
                                "uri": "http://127.0.0.1:1984/auth",
                                "request_headers": ["Authorization"],
                                "request_method": "POST"
                        },
  			"proxy-rewrite": {
                                "uri": "/echo"
			    }
			},			
			"upstream_id": "u1",
                        "uri": "/sanity"
                    }]],
                },
		{
                    url = "/apisix/admin/routes/11",
                    data = [[{
                        "plugins": {
                        "forward-auth": {
                                "uri": "http://127.0.0.1:1984/auth",
                                "request_headers": ["Authorization"],
                                "request_method": "POST",
				"forward_by_streaming": false
                        },
  			"proxy-rewrite": {
                                "uri": "/echo"
			    }
			},			
			"upstream_id": "u1",
                        "uri": "/sanity_download"
                    }]],
                },
		{
                    url = "/apisix/admin/routes/12",
                    data = [[{
                        "plugins": {
                        "forward-auth": {
                                "uri": "http://127.0.0.1:1984/auth",
                                "request_headers": ["Authorization"],
                                "request_method": "POST",
				"forward_client_body": false
                        },
  			"proxy-rewrite": {
                                "uri": "/echo"
			    }
			},			
			"upstream_id": "u1",
                        "uri": "/sanity_not_forward"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/2",
                    data = [[{
                        "plugins": {
                        "forward-auth": {
                                "uri": "http://127.0.0.1:1984/auth",
                                "request_headers": ["Authorization"],
                                "request_method": "POST",
                                "allow_degradation": true
                        },
  			"proxy-rewrite": {
                                "uri": "/echo"
			    }
			},			
			"upstream_id": "u1",
                        "uri": "/partially_forwarded"
                    }]],
                },
		{
                    url = "/apisix/admin/routes/21",
                    data = [[{
                        "plugins": {
                        "forward-auth": {
                                "uri": "http://127.0.0.1:1984/auth",
                                "request_headers": ["Authorization"],
                                "request_method": "POST",
                                "allow_degradation": true,
				"forward_by_streaming": false
                        },
  			"proxy-rewrite": {
                                "uri": "/echo"
			    }
			},			
			"upstream_id": "u1",
                        "uri": "/partially_forwarded_download"
                    }]],
                },
                {
                    url = "/apisix/admin/routes/3",
                    data = [[{
                        "plugins": {
                            "forward-auth": {
                                "uri": "http://127.39.40.1:9999/auth",
                                "request_headers": ["Authorization"],
                                "request_method": "POST",
                                "allow_degradation": true,
				"timeout": 100
                            },
                            "proxy-rewrite": {
                                "uri": "/echo"
                            }
                        },
                        "upstream_id": "u1",
                        "uri": "/connect_auth_svc_not_exists"
                    }]],
                },
		{
                    url = "/apisix/admin/routes/31",
                    data = [[{
                        "plugins": {
                            "forward-auth": {
                                "uri": "http://127.39.40.1:9999/auth",
                                "request_headers": ["Authorization"],
                                "request_method": "POST",
                                "allow_degradation": true,
				"timeout": 100,
				"forward_by_streaming": false
                            },
                            "proxy-rewrite": {
                                "uri": "/echo"
                            }
                        },
                        "upstream_id": "u1",
                        "uri": "/connect_auth_svc_not_exists_download"
                    }]],
                }
            }

            local t = require("lib.test_admin").test

            for _, data in ipairs(data) do
                local code, body = t(data.url, ngx.HTTP_PUT, data.data)
                ngx.say(body)
            end
        }
    }
--- response_body eval
"passed\n" x 10



=== TEST 2: sanity - forward to auth. service then proxy_psss to upstream
--- pipelined_requests eval
[
"POST /sanity\n" . $::tempfile_body,
"POST /sanity\n" . $::memory_body,
"POST /sanity_download\n" . $::tempfile_body,
"POST /sanity_download\n" . $::memory_body,
]
--- more_headers
Authorization: read-whole-client-body
--- error_code eval
[200, 200, 200, 200]
--- response_body eval
[
$::tempfile_body_md5,
$::memory_body_md5,
$::tempfile_body_md5,
$::memory_body_md5,
]



=== TEST 3: sanity - not forward to auth. service
--- pipelined_requests eval
[
"POST /sanity_not_forward\n" . $::tempfile_body,
"POST /sanity_not_forward\n" . $::memory_body,
]
--- more_headers
Authorization: read-whole-client-body
--- error_code eval
[200, 200]
--- response_body eval
[
$::tempfile_body_md5,
$::memory_body_md5,
]



=== TEST 4: [allow_degradation=true] client body has partially forwarded to auth. service
--- pipelined_requests eval
[
"POST /partially_forwarded\n" . $::tempfile_body,
"POST /partially_forwarded\n" . $::memory_body,
"POST /partially_forwarded_download\n" . $::tempfile_body,
"POST /partially_forwarded_download\n" . $::memory_body,
]
--- more_headers
Authorization: simulate-partially-read-client-body
--- error_code eval
[200, 200, 200, 200]
--- ignore_error_log
--- response_body eval
[
$::tempfile_body_md5,
$::memory_body_md5,
$::tempfile_body_md5,
$::memory_body_md5,
]



=== TEST 5: [allow_degradation=true] client body has not started to forward to auth. service
--- pipelined_requests eval
[
"POST /connect_auth_svc_not_exists\n" . $::tempfile_body,
"POST /connect_auth_svc_not_exists\n" . $::memory_body,
"POST /connect_auth_svc_not_exists_download\n" . $::tempfile_body,
"POST /connect_auth_svc_not_exists_download\n" . $::memory_body,
]
--- more_headers
Authorization: read-whole-client-body
--- error_code eval
[200, 200, 200, 200]
--- response_body eval
[
$::tempfile_body_md5,
$::memory_body_md5,
$::tempfile_body_md5,
$::memory_body_md5,
]
