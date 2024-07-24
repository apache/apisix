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

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});
run_tests();

__DATA__

=== TEST 1: authz-casdoor no https
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-casdoor")
            local fake_uri = "http://127.0.0.1:" .. ngx.var.server_port
            local callback_url = "http://127.0.0.1:" .. ngx.var.server_port ..
                                    "/anything/callback"
            local conf = {
                callback_url = callback_url,
                endpoint_addr = fake_uri,
                client_id = "7ceb9b7fda4a9061ec1c",
                client_secret = "3416238e1edf915eac08b8fe345b2b95cdba7e04"
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")

        }
    }
--- response_body
done
--- error_log
Using authz-casdoor endpoint_addr with no TLS is a security risk
Using authz-casdoor callback_url with no TLS is a security risk



=== TEST 2: authz-casdoor with TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.authz-casdoor")
            local fake_uri = "https://127.0.0.1:" .. ngx.var.server_port
            local callback_url = "https://127.0.0.1:" .. ngx.var.server_port ..
                                    "/anything/callback"
            local conf = {
                callback_url = callback_url,
                endpoint_addr = fake_uri,
                client_id = "7ceb9b7fda4a9061ec1c",
                client_secret = "3416238e1edf915eac08b8fe345b2b95cdba7e04"
            }
            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end
            ngx.say("done")

        }
    }
--- response_body
done
--- no_error_log
Using authz-casdoor endpoint_addr with no TLS is a security risk
Using authz-casdoor callback_url with no TLS is a security risk



=== TEST 3: authz keycloak with no TLS
--- config
    location /t {
        content_by_lua_block {
            local check = {"discovery", "token_endpoint", "resource_registration_endpoint", "access_denied_redirect_uri"}
            local plugin = require("apisix.plugins.authz-keycloak")
            local ok, err = plugin.check_schema({
                                client_id = "foo",
                                discovery = "http://host.domain/realms/foo/protocol/openid-connect/token",
                                token_endpoint = "http://token_endpoint.domain",
                                resource_registration_endpoint = "http://resource_registration_endpoint.domain",
                                access_denied_redirect_uri = "http://access_denied_redirect_uri.domain"
                            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- error_log
Using authz-keycloak discovery with no TLS is a security risk
Using authz-keycloak token_endpoint with no TLS is a security risk
Using authz-keycloak resource_registration_endpoint with no TLS is a security
Using authz-keycloak access_denied_redirect_uri with no TLS is a security risk



=== TEST 4: authz keycloak with TLS
--- config
    location /t {
        content_by_lua_block {
            local check = {"discovery", "token_endpoint", "resource_registration_endpoint", "access_denied_redirect_uri"}
            local plugin = require("apisix.plugins.authz-keycloak")
            local ok, err = plugin.check_schema({
                                client_id = "foo",
                                discovery = "https://host.domain/realms/foo/protocol/openid-connect/token",
                                token_endpoint = "https://token_endpoint.domain",
                                resource_registration_endpoint = "https://resource_registration_endpoint.domain",
                                access_denied_redirect_uri = "https://access_denied_redirect_uri.domain"
                            })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
Using authz-keycloak discovery with no TLS is a security risk
Using authz-keycloak token_endpoint with no TLS is a security risk
Using authz-keycloak resource_registration_endpoint with no TLS is a security
Using authz-keycloak access_denied_redirect_uri with no TLS is a security risk



=== TEST 5: cas auth with no TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.cas-auth")
            local ok, err = plugin.check_schema({
                idp_uri = "http://a.com",
                cas_callback_uri = "/a/b",
                logout_uri = "/c/d"
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
passed
--- error_log
risk



=== TEST 6: cas auth with TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.cas-auth")
            local ok, err = plugin.check_schema({
                idp_uri = "https://a.com",
                cas_callback_uri = "/a/b",
                logout_uri = "/c/d"
            })
            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
passed
--- no_error_log
risk



=== TEST 7: clickhouse logger with no TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.clickhouse-logger")
            local ok, err = plugin.check_schema({
                timeout = 3,
                retry_delay = 1,
                batch_max_size = 500,
                user = "default",
                password = "a",
                database = "default",
                logtable = "t",
                endpoint_addrs = {
                    "http://127.0.0.1:1980/clickhouse_logger_server",
                    "http://127.0.0.2:1980/clickhouse_logger_server",
                },
                max_retry_count = 1,
                name = "clickhouse logger",
                ssl_verify = false
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
passed
--- error_log
Using clickhouse-logger endpoint_addrs with no TLS is a security risk



=== TEST 8: clickhouse logger with TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.clickhouse-logger")
            local ok, err = plugin.check_schema({
                timeout = 3,
                retry_delay = 1,
                batch_max_size = 500,
                user = "default",
                password = "a",
                database = "default",
                logtable = "t",
                endpoint_addrs = {
                    "https://127.0.0.1:1980/clickhouse_logger_server",
                    "https://127.0.0.2:1980/clickhouse_logger_server",
                },
                max_retry_count = 1,
                name = "clickhouse logger",
                ssl_verify = false
            })

            if not ok then
                ngx.say(err)
            else
                ngx.say("passed")
            end
        }
    }
--- response_body
passed
--- no_error_log
Using clickhouse-logger endpoint_addrs with no TLS is a security risk



=== TEST 9: elastic search logger with no TLS
--- config
    location /t {
        content_by_lua_block {
            local ok, err
            local plugin = require("apisix.plugins.elasticsearch-logger")
                ok, err = plugin.check_schema({
                    endpoint_addrs = {
                        "http://127.0.0.1:9200"
                    },
                    field = {
                        index = "services"
                    }
                })
                if err then
                    ngx.say(err)
                else
                    ngx.say("passed")
                end

        }
    }
--- response_body_like
passed
--- error_log
Using elasticsearch-logger endpoint_addrs with no TLS is a security risk



=== TEST 10: elastic search logger with TLS
--- config
    location /t {
        content_by_lua_block {
            local ok, err
            local plugin = require("apisix.plugins.elasticsearch-logger")
                ok, err = plugin.check_schema({
                    endpoint_addrs = {
                        "https://127.0.0.1:9200"
                    },
                    field = {
                        index = "services"
                    }
                })
                if err then
                    ngx.say(err)
                else
                    ngx.say("passed")
                end

        }
    }
--- response_body_like
passed
--- no_error_log
Using elasticsearch-logger endpoint_addrs with no TLS is a security risk



=== TEST 11: error log logger with tcp.tls = false
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



=== TEST 12: error log logger with tcp.tls = true
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



=== TEST 13: forward auth with no TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.forward-auth")

            local ok, err = plugin.check_schema({uri = "http://127.0.0.1:8199"})
            ngx.say(ok and "done" or err)

        }
    }
--- response_body
done
--- error_log
Using forward-auth uri with no TLS is a security risk
Using forward-auth uri with no TLS is a security risk



=== TEST 14: forward auth with TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.forward-auth")

            local ok, err = plugin.check_schema({uri = "https://127.0.0.1:8199"})
            ngx.say(ok and "done" or err)

        }
    }
--- response_body
done
--- no_error_log
Using forward-auth uri with no TLS is a security risk



=== TEST 15: http-logger with no TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.http-logger")
            local ok, err = plugin.check_schema({uri = "http://127.0.0.1"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
Using http-logger uri with no TLS is a security risk



=== TEST 16: http-logger with TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.http-logger")
            local ok, err = plugin.check_schema({uri = "https://127.0.0.1"})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- no_error_log
Using http-logger uri with no TLS is a security risk



=== TEST 17: ldap auth with no TLS
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.ldap-auth")
            local ok, err = plugin.check_schema(
                {
                    base_dn = "123",
                    ldap_uri = "127.0.0.1:1389",
                    tls_verify = false,
                    use_tls = false
                })
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- error_log
Keeping tls_verify disabled in ldap-auth configuration is a security risk
Keeping use_tls disabled in ldap-auth configuration is a security risk



=== TEST 18: ldap auth with TLS
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.ldap-auth")
            local ok, err = plugin.check_schema({base_dn = "123", ldap_uri = "127.0.0.1:1389", use_tls = true})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done
--- no_error_log
Using LDAP auth with TLS disabled is a security risk



=== TEST 19: loki-logger with no TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.loki-logger")

            local ok, err = plugin.check_schema({endpoint_addrs = {"http://127.0.0.1:8199"}})
            ngx.say(ok and "done" or err)
        }
    }
--- response_body
done
--- error_log
Using loki-logger endpoint_addrs with no TLS is a security risk
Using loki-logger endpoint_addrs with no TLS is a security risk
Using loki-logger endpoint_addrs with no TLS is a security risk



=== TEST 20: loki logger with TLS
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.loki-logger")

            local ok, err = plugin.check_schema({endpoint_addrs = {"https://127.0.0.1:8199"}})
            ngx.say(ok and "done" or err)
        }
    }
--- response_body
done
--- no_error_log
Using loki-logger endpoint_addrs with no TLS is a security risk
