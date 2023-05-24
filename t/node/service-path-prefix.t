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
log_level('warn');
no_root_location();
no_shuffle();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    my $extra_init_worker_by_lua = $block->extra_init_worker_by_lua // "";
    $extra_init_worker_by_lua .= <<_EOC_;
function test_path_prefix()
    local t = require("lib.test_admin")

    assert(t.test('/apisix/admin/services/1',
        ngx.HTTP_PUT,
        [[
            {
                \"plugins\": {
                    \"proxy-rewrite\": {
                        \"regex_uri\": [\"^/foo/(.*)\",\"/\$1\"]
                    }
                },
                \"path_prefix\": \"/foo\",
                \"upstream\": {
                    \"type\": \"roundrobin\",
                    \"nodes\": {
                        \"127.0.0.1:1980\": 1
                    }
                }
            }
        ]]
    ))
    ngx.sleep(0.5)

    assert(t.test('/apisix/admin/routes/1',
        ngx.HTTP_PUT,
        [[
            {
                \"uri\": \"/hello\",
                \"service_id\": \"1\"
            }
        ]]
    ))
    ngx.sleep(0.5)

    local http = require "resty.http"
    local httpc = http.new()
    local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/foo/hello"
    local res, err = httpc:request_uri(uri)
    ngx.status = res.status
    ngx.print(res.body)
end

function test_strip_path_prefix()
    local t = require("lib.test_admin")

    assert(t.test('/apisix/admin/services/1',
        ngx.HTTP_PUT,
        [[
            {
                \"path_prefix\": \"/foo\",
                \"upstream\": {
                    \"type\": \"roundrobin\",
                    \"nodes\": {
                        \"127.0.0.1:1980\": 1
                    }
                }
            }
        ]]
    ))
    ngx.sleep(0.5)

    assert(t.test('/apisix/admin/routes/1',
        ngx.HTTP_PUT,
        [[
            {
                \"uri\": \"/hello\",
                \"service_id\": \"1\",
                \"strip_path_prefix\": true
            }
        ]]
    ))
    ngx.sleep(0.5)

    local http = require "resty.http"
    local httpc = http.new()
    local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/foo/hello"
    local res, err = httpc:request_uri(uri)
    ngx.status = res.status
    ngx.print(res.body)
end
_EOC_
    $block->set_value("extra_init_worker_by_lua", $extra_init_worker_by_lua);
});

run_tests();

__DATA__

=== TEST 1: test service path_prefix: radixtree_host_uri
--- yaml_config
apisix:
  router:
    http: 'radixtree_host_uri'
--- config
    location /t {
        content_by_lua_block {
            test_path_prefix()
        }
    }
--- response_body
hello world



=== TEST 2: test service strip_path_prefix: radixtree_host_uri
--- yaml_config
apisix:
  router:
    http: 'radixtree_host_uri'
--- config
    location /t {
        content_by_lua_block {
            test_strip_path_prefix()
        }
    }
--- response_body
hello world



=== TEST 3: test service path_prefix: radixtree_uri_with_parameter
--- yaml_config
apisix:
  router:
    http: 'radixtree_uri_with_parameter'
--- config
    location /t {
        content_by_lua_block {
            test_path_prefix()
        }
    }
--- response_body
hello world



=== TEST 4: test service strip_path_prefix: radixtree_uri_with_parameter
--- yaml_config
apisix:
  router:
    http: 'radixtree_uri_with_parameter'
--- config
    location /t {
        content_by_lua_block {
            test_strip_path_prefix()
        }
    }
--- response_body
hello world



=== TEST 5: test service path_prefix: radixtree_uri
--- yaml_config
apisix:
  router:
    http: 'radixtree_uri'
--- config
    location /t {
        content_by_lua_block {
            test_path_prefix()
        }
    }
--- response_body
hello world



=== TEST 6: test service strip_path_prefix: radixtree_uri
--- yaml_config
apisix:
  router:
    http: 'radixtree_uri'
--- config
    location /t {
        content_by_lua_block {
            test_strip_path_prefix()
        }
    }
--- response_body
hello world
