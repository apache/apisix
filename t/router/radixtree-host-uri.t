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
log_level('info');
worker_connections(256);
no_root_location();
no_shuffle();

sub read_file($) {
    my $infile = shift;
    open my $in, $infile
        or die "cannot open $infile for reading: $!";
    my $cert = do { local $/; <$in> };
    close $in;
    $cert;
}

our $yaml_config = read_file("conf/config.yaml");
$yaml_config =~ s/node_listen: 9080/node_listen: 1984/;
$yaml_config =~ s/enable_heartbeat: true/enable_heartbeat: false/;
$yaml_config =~ s/http: 'radixtree_uri'/http: 'radixtree_host_uri'/;

run_tests();

__DATA__

=== TEST 1: set route(host + uri)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "host": "foo.com",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- yaml_config eval: $::yaml_config
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: /not_found
--- request
GET /not_found
--- yaml_config eval: $::yaml_config
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 3: /not_found
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 4: /not_found
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- more_headers
Host: not_found.com
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 5: hit routes
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- more_headers
Host: foo.com
--- response_body
hello world
--- no_error_log
[error]



=== TEST 6: hit routes
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- more_headers
Host: foo.com
--- response_body
hello world



=== TEST 7: set route(only uri)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/server_port",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1981": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- yaml_config eval: $::yaml_config
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 8: /not_found
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 9: hit routes
--- request
GET /server_port
--- yaml_config eval: $::yaml_config
--- more_headers
Host: anydomain.com
--- response_body_like eval
qr/1981/
--- no_error_log
[error]



=== TEST 10: set route(only uri + id: 2)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1981": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- yaml_config eval: $::yaml_config
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 11: /not_found
--- request
GET /hello2
--- yaml_config eval: $::yaml_config
--- error_code: 404
--- response_body eval
qr/404 Not Found/
--- no_error_log
[error]



=== TEST 12: hit routes
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- more_headers
Host: anydomain.com
--- response_body
hello world
--- no_error_log
[error]



=== TEST 13: delete route(id: 2)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_DELETE
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- yaml_config eval: $::yaml_config
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 14: set route(wildcard host + uri)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "/hello",
                    "host": "*.foo.com",
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- yaml_config eval: $::yaml_config
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 15: hit routes
--- request
GET /hello
--- yaml_config eval: $::yaml_config
--- more_headers
Host: www.foo.com
--- response_body
hello world
