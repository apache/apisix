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
no_shuffle();

add_block_preprocessor(sub {
	my ($block) = @_;
	if (!defined $block->request) {
		$block->set_value("request", "GET /t");
	}
});

run_tests();

__DATA__

=== TEST 1: sanity
--- config
	location /t {
		content_by_lua_block {
			local ok, err
			local configs = {
				{
					auth = { username = "user", password = "pass" },
					etcd = { urls = [ "http://127.0.0.1:2379" ], key_prefix = "/apisix/logs" },
				},
				{
					auth = { username = "user" },
					etcd = { urls = [ "http://127.0.0.1:2379" ] },
				},
				{
					auth = { username = "user", password = "pass" },
					etcd = {},
				},
			}
			local plugin = require("apisix.plugins.etcd-logger")
			for i = 1, #configs do
				ok, err = plugin.check_schema(configs[i])
				if ok then
					ngx.say("passed")
				else
					ngx.say(err)
				end
			end
		}
	}
--- response_body_like
passed
property "password" is required
property "etcd" validation failed: property "urls" is required


=== TEST 2: set route
--- config
	location /t {
		content_by_lua_block {
			local t = require("lib.test_admin").test
			local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, {
				uri = "/hello",
				plugins = {
					["etcd-logger-test"] = {
						auth = { username = "user", password = "pass" },
						etcd = { urls = [ "http://127.0.0.1:2379" ], key_prefix = "/apisix/logs" },
					}
				},
				upstream = { type = "roundrobin", nodes = { ["127.0.0.1:1980"] = 1 } }
			})
			if code >= 300 then
				ngx.status = code
			end
			ngx.say(body)
		}
	}
--- response_body
passed


=== TEST 3: test route (success write)
--- extra_init_by_lua
	local core = require("apisix.core")
	local http = require("resty.http")
	local log_util = require("apisix.utils.log-util")
	log_util.inject_get_full_log(function(ngx, conf)
		return { test = "test" }
	end)
	http.request_uri = function(self, uri, params)
		if params.method == "POST" and uri:find("/v3/kv/put", 1, true) then
			local entry = core.json.decode(params.body)
			local value = core.json.decode(core.base64.decode(entry.value))
			if value.test == "test" then
				core.log.error("check etcd full log body success")
				return { status = 200, body = "success" }, nil
			else
				return nil, "invalid log body"
			end
		end
		if params.method == "POST" and uri:find("/v3/auth/authenticate", 1, true) then
			return { status = 200, body = '{"token":"dummy-token"}' }, nil
		end
		if params.method == "POST" and uri:find("/v3/lease/grant", 1, true) then
			return { status = 200, body = '{"ID":12345}' }, nil
		end
		return nil, "unexpected uri"
	end
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- error_log
check etcd full log body success


=== TEST 4: set route (auth fail)
--- config
	location /t {
		content_by_lua_block {
			local t = require("lib.test_admin").test
			local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, {
				uri = "/hello",
				plugins = {
					["etcd-logger-test"] = {
						auth = { username = "user", password = "badpass" },
						etcd = { urls = [ "http://127.0.0.1:2379" ], key_prefix = "/apisix/logs" },
					}
				},
				upstream = { type = "roundrobin", nodes = { ["127.0.0.1:1980"] = 1 } }
			})
			if code >= 300 then
				ngx.status = code
			end
			ngx.say(body)
		}
	}
--- response_body
passed


=== TEST 5: test route (auth fail)
--- extra_init_by_lua
	local http = require("resty.http")
	http.request_uri = function(self, uri, params)
		if params.method == "POST" and uri:find("/v3/auth/authenticate", 1, true) then
			return nil, "auth failed"
		end
		return nil, "unexpected uri"
	end
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- error_log
cannot send to etcd, authentication failed: auth failed


=== TEST 6: set route (lease fail)
--- config
	location /t {
		content_by_lua_block {
			local t = require("lib.test_admin").test
			local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, {
				uri = "/hello",
				plugins = {
					["etcd-logger-test"] = {
						auth = { username = "user", password = "pass" },
						etcd = { urls = [ "http://127.0.0.1:2379" ], key_prefix = "/apisix/logs", ttl = 10 },
					}
				},
				upstream = { type = "roundrobin", nodes = { ["127.0.0.1:1980"] = 1 } }
			})
			if code >= 300 then
				ngx.status = code
			end
			ngx.say(body)
		}
	}
--- response_body
passed


=== TEST 7: test route (lease fail)
--- extra_init_by_lua
	local http = require("resty.http")
	http.request_uri = function(self, uri, params)
		if params.method == "POST" and uri:find("/v3/auth/authenticate", 1, true) then
			return { status = 200, body = '{"token":"dummy-token"}' }, nil
		end
		if params.method == "POST" and uri:find("/v3/lease/grant", 1, true) then
			return nil, "lease grant failed"
		end
		return nil, "unexpected uri"
	end
--- request
GET /hello
--- wait: 2
--- response_body
hello world
--- error_log
cannot send to etcd, failed to get lease: lease grant failed


=== TEST 8: data encryption for auth.password
--- yaml_config
apisix:
	data_encryption:
		enable_encrypt_fields: true
		keyring:
			- edd1c9f0985e76a2
--- config
	location /t {
		content_by_lua_block {
			local json = require("toolkit.json")
			local t = require("lib.test_admin").test
			local code, body = t('/apisix/admin/routes/1', ngx.HTTP_PUT, {
				uri = "/hello",
				plugins = {
					["etcd-logger-test"] = {
						auth = { username = "user", password = "123456" },
						etcd = { urls = [ "http://127.0.0.1:2379" ], key_prefix = "/apisix/logs" },
					}
				},
				upstream = { type = "roundrobin", nodes = { ["127.0.0.1:1980"] = 1 } }
			})
			if code >= 300 then
				return
			end
			ngx.sleep(0.1)
			local code, message, res = t('/apisix/admin/routes/1')
			res = json.decode(res)
			if code >= 300 then
				return
			end
			ngx.say(res.value.plugins["etcd-logger-test"].auth.password)
			local etcd = require("apisix.core.etcd")
			local res = assert(etcd.get('/routes/1'))
			ngx.say(res.body.node.value.plugins["etcd-logger-test"].auth.password)
		}
	}
--- response_body_like
123456
.+
