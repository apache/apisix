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

workers(3);

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests();

__DATA__

=== TEST 1: continue to get nacos data after failure in a service
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  nacos:
      host:
        - "http://127.0.0.1:20999"
      prefix: "/nacos/v1/"
      fetch_interval: 1
      weight: 1
      timeout:
        connect: 2000
        send: 2000
        read: 5000
--- apisix_yaml
routes:
  -
    uri: /hello_
    upstream:
      service_name: NOT-NACOS
      discovery_type: nacos
      type: roundrobin
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin
#END
--- http_config
    server {
        listen 20999;

        location / {
            access_by_lua_block {
                if not package.loaded.hit then
                    package.loaded.hit = true
                    ngx.exit(502)
                end
            }
            proxy_pass http://127.0.0.1:8858;
        }
    }
--- request
GET /hello
--- response_body_like eval
qr/server [1-2]/
--- error_log
err:status = 502



=== TEST 2: change nacos server auth password
--- config
    location /t {
        content_by_lua_block {
            local json = require("cjson")
            local http = require("resty.http")

            local httpc = http.new()
            local nacos_host = "http://127.0.0.1:8848"
            local res, err = httpc:request_uri(nacos_host .. "/nacos/v1/auth/login", {
                    method = "POST",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded",
                    },
                    body = ngx.encode_args({username = "nacos", password = "nacos"}),
                })

            if res.status ~= 200 then
                ngx.say("nacos auth failed")
                ngx.exit(401)
            end

            local res_json = json.decode(res.body)
            res, err = httpc:request_uri(nacos_host .. "/nacos/v1/auth/users?accessToken=" .. res_json["accessToken"], {
                    method = "PUT",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded",
                    },
                    body = ngx.encode_args({username = "nacos", newPassword = "nacos!@#$%^&*()[]"}),
                })
            if res.status ~= 200 then
                ngx.say("nacos token auth failed")
                ngx.say(res.body)
                ngx.exit(401)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 3: test complex host
--- extra_yaml_config
discovery:
  nacos:
      host:
        - "http://nacos:nacos!@#$%^&*()[]@127.0.0.1:8848"
      fetch_interval: 1
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin

#END
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local uri = "http://127.0.0.1:" .. ngx.var.server_port

            -- Wait for 2 seconds for APISIX initialization
            ngx.sleep(2)
            local httpc = http.new()
            local valid_responses = 0

            for i = 1, 2 do
                local res, err = httpc:request_uri(uri .. "/hello")
                if not res then
                    ngx.log(ngx.ERR, "Request failed: ", err)
                else
                    -- Clean and validate response
                    local clean_body = res.body:gsub("%s+$", "")
                    if clean_body == "server 1" or clean_body == "server 2" then
                        valid_responses = valid_responses + 1
                    else
                        ngx.log(ngx.ERR, "Invalid response: ", clean_body)
                    end
                end
            end
            -- Final check
            if valid_responses == 2 then
                ngx.say("PASS")
            else
                ngx.say("FAIL: only ", valid_responses, " valid responses")
            end
        }
    }
--- request
GET /t
--- response_body
PASS



=== TEST 4: restore nacos server auth password
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin

#END
--- config
    location /t {
        content_by_lua_block {
            local json = require("cjson")
            local http = require("resty.http")

            local httpc = http.new()
            local nacos_host = "http://127.0.0.1:8848"
            local res, err = httpc:request_uri(nacos_host .. "/nacos/v1/auth/login", {
                    method = "POST",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded",
                    },
                    body = ngx.encode_args({username = "nacos", password = "nacos!@#$%^&*()[]"}),
                })

            if res.status ~= 200 then
                ngx.say("nacos auth failed")
                ngx.exit(401)
            end

            local res_json = json.decode(res.body)
            res, err = httpc:request_uri(nacos_host .. "/nacos/v1/auth/users?accessToken=" .. res_json["accessToken"], {
                    method = "PUT",
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded",
                    },
                    body = ngx.encode_args({username = "nacos", newPassword = "nacos"}),
                })
            if res.status ~= 200 then
                ngx.say("nacos token auth failed")
                ngx.say(res.body)
                ngx.exit(401)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 5: same service is registered in route, service and upstream, de-duplicate
--- yaml_config
apisix:
  node_listen: 1984
--- extra_yaml_config
discovery:
  nacos:
      host:
        - "http://127.0.0.1:8858"
      fetch_interval: 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test

            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello",
                    "upstream": {
                        "service_name": "APISIX-NACOS",
                        "discovery_type": "nacos",
                        "scheme": "http",
                        "type": "roundrobin",
                        "discovery_args": {
                          "namespace_id": "public",
                          "group_name": "DEFAULT_GROUP"
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end

            local code, body = t('/apisix/admin/services/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "type": "roundrobin",
                        "scheme": "http",
                        "discovery_type": "nacos",
                        "pass_host": "pass",
                        "service_name": "APISIX-NACOS",
                        "discovery_args": {
                          "namespace_id": "public",
                          "group_name": "DEFAULT_GROUP"
                        }
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end

            local code, body = t('/apisix/admin/upstreams/1',
                ngx.HTTP_PUT,
                [[{
                    "type": "roundrobin",
                    "scheme": "http",
                    "discovery_type": "nacos",
                    "pass_host": "pass",
                    "service_name": "APISIX-NACOS",
                    "discovery_args": {
                    "namespace_id": "public",
                    "group_name": "DEFAULT_GROUP"
                    }
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end

            ngx.sleep(1.5)

            local json_decode = require("toolkit.json").decode
            local http = require "resty.http"
            local httpc = http.new()
            local dump_uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/v1/discovery/nacos/dump"
            local res, err = httpc:request_uri(dump_uri, { method = "GET"})
            if err then
                ngx.log(ngx.ERR, err)
                ngx.status = res.status
                return
            end

            local body = json_decode(res.body)
            local services = body.services
            local service = services["default/public/DEFAULT_GROUP/APISIX-NACOS"]
            local number = table.getn(service.nodes)
            ngx.say(number)
        }
    }
--- response_body
2



=== TEST 6: fallback to next nacos host when current host fails
--- yaml_config
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
discovery:
    nacos:
            host:
                - "http://127.0.0.1:20998"
                - "http://127.0.0.1:8858"
            prefix: "/nacos/v1/"
            fetch_interval: 1
            weight: 1
            timeout:
                connect: 2000
                send: 2000
                read: 5000
--- apisix_yaml
routes:
    -
        uri: /hello
        upstream:
            service_name: APISIX-NACOS
            discovery_type: nacos
            type: roundrobin
#END
--- http_config
        server {
                listen 20998;

                location / {
                        return 502;
                }
        }
--- request
GET /hello
--- response_body_like eval
qr/server [1-2]/
--- error_log
fetch_from_host: http://127.0.0.1:20998/nacos/v1/ err:all nacos services fetch failed



=== TEST 7: keep cached nodes of a service whose refresh fails
--- yaml_config
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
discovery:
  nacos:
      host:
        - "http://127.0.0.1:20997"
      prefix: "/nacos/v1/"
      fetch_interval: 1
      weight: 1
      timeout:
        connect: 2000
        send: 2000
        read: 5000
--- apisix_yaml
routes:
  -
    uri: /hello
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin
  -
    uri: /hello_test_group
    upstream:
      service_name: APISIX-NACOS
      discovery_type: nacos
      type: roundrobin
      discovery_args:
        group_name: test_group
#END
--- http_config
    server {
        listen 20997;

        location / {
            access_by_lua_block {
                -- let the first query of the test_group service succeed so that
                -- its nodes get cached, then fail every later query for it
                if string.find(ngx.var.args or "", "groupName=test_group") then
                    local hits = ngx.shared.nacos:incr("test:test_group_queries", 1, 0)
                    if hits > 1 then
                        ngx.exit(502)
                    end
                end
            }
            proxy_pass http://127.0.0.1:8858;
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local http = require("resty.http")
            local base = "http://127.0.0.1:" .. ngx.var.server_port
            local httpc = http.new()

            -- wait for the first refresh to cache both services
            ngx.sleep(2.5)

            local res = httpc:request_uri(base .. "/hello_test_group")
            if not res or res.status ~= 200 then
                ngx.say("FAIL: initial request for the test_group service: ",
                        res and res.status or "no response")
                return
            end

            -- the test_group query now fails, while the default group one still
            -- succeeds, so the refresh commits without the failed service
            ngx.sleep(3)

            res = httpc:request_uri(base .. "/hello_test_group")
            if not res or res.status ~= 200 then
                ngx.say("FAIL: cached nodes dropped after a failed refresh: ",
                        res and res.status or "no response")
                return
            end

            res = httpc:request_uri(base .. "/hello")
            if not res or res.status ~= 200 then
                ngx.say("FAIL: request for the healthy service: ",
                        res and res.status or "no response")
                return
            end

            ngx.say("PASS")
        }
    }
--- timeout: 15
--- request
GET /t
--- response_body
PASS
--- error_log
err:status = 502



=== TEST 8: delete cached nodes once the service is no longer referenced
--- yaml_config
apisix:
  node_listen: 1984
--- extra_yaml_config
discovery:
  nacos:
      host:
        - "http://127.0.0.1:8858"
      fetch_interval: 1
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local json_decode = require("toolkit.json").decode
            local http = require("resty.http")
            local httpc = http.new()

            local code, body = t('/apisix/admin/upstreams/1',
                 ngx.HTTP_PUT,
                 [[{
                    "service_name": "APISIX-NACOS",
                    "discovery_type": "nacos",
                    "type": "roundrobin"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/upstreams/2',
                 ngx.HTTP_PUT,
                 [[{
                    "service_name": "APISIX-NACOS",
                    "discovery_type": "nacos",
                    "type": "roundrobin",
                    "discovery_args": {
                        "group_name": "test_group"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello",
                    "upstream_id": 1
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "uri": "/hello_test_group",
                    "upstream_id": 2
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(2)

            local function dump_services()
                local res = httpc:request_uri(
                    "http://127.0.0.1:" .. ngx.var.server_port
                    .. "/v1/discovery/nacos/dump", { method = "GET" })
                if not res or res.status ~= 200 then
                    return nil
                end
                return (json_decode(res.body) or {}).services
            end

            local services = dump_services()
            if not services
                    or not services["default/public/DEFAULT_GROUP/APISIX-NACOS"]
                    or not services["default/public/test_group/APISIX-NACOS"] then
                ngx.say("FAIL: both services should be cached")
                return
            end

            -- remove the test_group service from the APISIX configuration
            code, body = t('/apisix/admin/routes/2', ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            code, body = t('/apisix/admin/upstreams/2', ngx.HTTP_DELETE)
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            ngx.sleep(2)

            services = dump_services()
            if not services then
                ngx.say("FAIL: cannot dump nacos services")
                return
            end

            if services["default/public/test_group/APISIX-NACOS"] then
                ngx.say("FAIL: removed service is still cached")
                return
            end

            if not services["default/public/DEFAULT_GROUP/APISIX-NACOS"] then
                ngx.say("FAIL: still referenced service was deleted")
                return
            end

            ngx.say("PASS")
        }
    }
--- timeout: 15
--- request
GET /t
--- response_body
PASS
