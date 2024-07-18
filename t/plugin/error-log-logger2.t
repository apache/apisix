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

run_tests;

__DATA__

=== TEST 1: not using tls/http should give security warning
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.error-log-logger")
            local ok, err = plugin.check_schema({
                tcp = {
                    host = "host.com",
                    port = "99",
                    tls = false,
                },
                skywalking = {
                    endpoint_addr = "http://a.bcd"
                },
                clickhouse = {
                    endpoint_addr = "http://some.com",
                    user = "user",
                    password = "secret",
                    database = "yes",
                    logtable = "some"
                },
            })
            ngx.say(ok and "done" or err)

        }
    }
--- request
GET /t
--- response_body
done
--- error_log
Using error-log-logger skywalking.endpoint_addr with no TLS is a security risk
Using error-log-logger clickhouse.endpoint_addr with no TLS is a security risk
Keeping tcp.tls disabled in error-log-logger configuration is a security risk



=== TEST 2: using tls/https should not give security warning
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.error-log-logger")
            local ok, err = plugin.check_schema({
                tcp = {
                    host = "host.com",
                    port = "99",
                    tls = true,
                },
                skywalking = {
                    endpoint_addr = "https://a.bcd"
                },
                clickhouse = {
                    endpoint_addr = "https://some.com",
                    user = "user",
                    password = "secret",
                    database = "yes",
                    logtable = "some"
                },
            })
            ngx.say(ok and "done" or err)

        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
Using error-log-logger skywalking.endpoint_addr with no TLS is a security risk
Using error-log-logger clickhouse.endpoint_addr with no TLS is a security risk
Keeping tcp.tls disabled in error-log-logger configuration is a security risk
