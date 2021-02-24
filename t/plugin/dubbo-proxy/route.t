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
use t::APISIX;

my $nginx_binary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $version = eval { `$nginx_binary -V 2>&1` };

if ($version !~ m/\/mod_dubbo/) {
    plan(skip_all => "mod_dubbo not installed");
} else {
    plan('no_plan');
}

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->disable_dubbo) {
        my $extra_yaml_config = <<_EOC_;
plugins:
    - dubbo-proxy
    - response-rewrite
    - proxy-rewrite
_EOC_

        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }

    if (!$block->yaml_config) {
        my $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
_EOC_

        $block->set_value("yaml_config", $yaml_config);
    }

    if ($block->apisix_yaml) {
        my $upstream = <<_EOC_;
upstreams:
  - nodes:
        "127.0.0.1:20880": 1
    type: roundrobin
    id: 1
#END
_EOC_

        $block->set_value("apisix_yaml", $block->apisix_yaml . $upstream);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /hello");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: ignore route's dubbo configuration if dubbo is disable globally
--- disable_dubbo
--- apisix_yaml
routes:
  -
    uri: /hello
    plugins:
        dubbo-proxy:
            service_name: org.apache.dubbo.backend.DemoService
            service_version: 0.0.0
            method: hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
--- response_body
hello world



=== TEST 2: check schema
--- apisix_yaml
routes:
  -
    uri: /hello
    plugins:
        dubbo-proxy:
            service_name: org.apache.dubbo.backend.DemoService
            method: hello
    upstream_id: 1
--- error_log
property "service_version" is required
--- error_code: 404



=== TEST 3: sanity
--- apisix_yaml
routes:
  -
    uri: /hello
    plugins:
        dubbo-proxy:
            service_name: org.apache.dubbo.backend.DemoService
            service_version: 0.0.0
            method: hello
    upstream_id: 1
--- more_headers
Extra-Arg-K: V
--- response_headers
Got-extra-arg-k: V
--- response_body
dubbo success



=== TEST 4: enabled in service
--- apisix_yaml
routes:
  - uri: /hello
    service_id: 1

services:
    -
        plugins:
            dubbo-proxy:
                service_name: org.apache.dubbo.backend.DemoService
                service_version: 0.0.0
                method: hello
        id: 1
        upstream_id: 1
--- response_body
dubbo success



=== TEST 5: work with consumer
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: true
    admin_key: null
plugins:
    - key-auth
    - dubbo-proxy
--- config
    location /t {
        content_by_lua_block {
            local json = require("toolkit.json")
            local t = require("lib.test_admin").test

            local code, message = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                     "username":"jack",
                     "plugins": {
                        "key-auth": {
                            "key": "jack"
                        }
                     }
                }]]
            )

            if code >= 300 then
                ngx.status = code
                ngx.say(message)
                return
            end

            local code, message = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream":{
                        "nodes": {
                            "127.0.0.1:20880": 1
                        },
                        "type": "roundrobin"
                    },
                    "plugins": {
                        "dubbo-proxy": {
                            "service_name": "org.apache.dubbo.backend.DemoService",
                            "service_version": "0.0.0",
                            "method": "hello"
                        },
                        "key-auth": {}
                    },
                    "uris": ["/hello"]
                }]]
            )

            if code >= 300 then
                ngx.status = code
            end

            ngx.say(message)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 6: blocked
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: true
    admin_key: null
plugins:
    - key-auth
    - dubbo-proxy
--- error_code: 401



=== TEST 7: passed
--- yaml_config
apisix:
    node_listen: 1984
    enable_admin: true
    admin_key: null
plugins:
    - key-auth
    - dubbo-proxy
--- more_headers
apikey: jack
--- response_body
dubbo success



=== TEST 8: rewrite response
--- apisix_yaml
routes:
  -
    uri: /hello
    plugins:
        response-rewrite:
            headers:
                fruit: banana
            body: "hello world\n"
        dubbo-proxy:
            service_name: org.apache.dubbo.backend.DemoService
            service_version: 0.0.0
            method: hello
    upstream_id: 1

--- response_body
hello world
--- response_headers
fruit: banana



=== TEST 9: rewrite request
--- apisix_yaml
routes:
  -
    uri: /hello
    plugins:
        proxy-rewrite:
            headers:
                extra-arg-fruit: banana
        dubbo-proxy:
            service_name: org.apache.dubbo.backend.DemoService
            service_version: 0.0.0
            method: hello
    upstream_id: 1

--- response_body
dubbo success
--- response_headers
Got-extra-arg-fruit: banana



=== TEST 10: use uri as default method
--- apisix_yaml
routes:
  -
    uri: /hello
    plugins:
        dubbo-proxy:
            service_name: org.apache.dubbo.backend.DemoService
            service_version: 0.0.0
    upstream_id: 1

--- response_body
dubbo success
