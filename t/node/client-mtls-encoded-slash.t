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

if ($version !~ m/\/apisix-nginx-module/) {
    plan(skip_all => "apisix-nginx-module not installed");
} else {
    plan('no_plan');
}

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

our $yaml_config = <<_EOC_;
apisix:
    node_listen: 1984
    match_uri_encoded_slash: true
    router:
        http: 'radixtree_uri_with_parameter'
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->yaml_config) {
        $block->set_value("yaml_config", $yaml_config);
    }
});

run_tests();

__DATA__

=== TEST 1: set ssl with skip_mtls_uri_regex and routes
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin")
            local json = require("toolkit.json")
            local ssl_ca_cert = t.read_file("t/certs/mtls_ca.crt")
            local ssl_cert = t.read_file("t/certs/mtls_client.crt")
            local ssl_key = t.read_file("t/certs/mtls_client.key")

            local code, body = t.test('/apisix/admin/ssls/1',
                ngx.HTTP_PUT,
                json.encode({
                    cert = ssl_cert,
                    key = ssl_key,
                    sni = "localhost",
                    client = {
                        ca = ssl_ca_cert,
                        depth = 2,
                        skip_mtls_uri_regex = {
                            "^/public/status$",
                            "^/open/.*",
                        }
                    }
                })
            )
            if code >= 300 then
                ngx.status = code
                ngx.say(body)
                return
            end

            -- /hello1 marks the exempt routes, /hello the cert-only one
            local routes = {
                {id = 1, uri = "/public/status", target = "/hello1"},
                {id = 2, uri = "/open/:name", target = "/hello1"},
                {id = 3, uri = "/:resource", target = "/hello"},
            }
            for _, r in ipairs(routes) do
                local code, body = t.test('/apisix/admin/routes/' .. r.id,
                    ngx.HTTP_PUT,
                    json.encode({
                        uri = r.uri,
                        plugins = {
                            ["proxy-rewrite"] = {uri = r.target},
                        },
                        upstream = {
                            type = "roundrobin",
                            nodes = {["127.0.0.1:1980"] = 1},
                        },
                    })
                )
                if code >= 300 then
                    ngx.status = code
                    ngx.say(body)
                    return
                end
            end
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done



=== TEST 2: exempt uri skips the client cert
--- exec
curl -k https://localhost:1994/public/status
--- response_body eval
qr/hello1 world/



=== TEST 3: encoded slash routed off the exempt route requires the client cert
--- exec
curl -k https://localhost:1994/public%2Fstatus
--- response_body eval
qr/400 Bad Request/
--- error_log
client certificate was not present



=== TEST 4: lower case encoded slash requires the client cert
--- exec
curl -k https://localhost:1994/public%2fstatus
--- response_body eval
qr/400 Bad Request/
--- error_log
client certificate was not present



=== TEST 5: encoded slash with a valid client cert
--- exec
curl --cert t/certs/mtls_client.crt --key t/certs/mtls_client.key -k https://localhost:1994/public%2Fstatus
--- response_body eval
qr/hello world/



=== TEST 6: exempt pattern that covers the encoded form still skips the client cert
--- exec
curl -k https://localhost:1994/open/a%2Fb
--- response_body eval
qr/hello1 world/



=== TEST 7: without match_uri_encoded_slash the encoded slash hits the exempt route
--- yaml_config
apisix:
    node_listen: 1984
    router:
        http: 'radixtree_uri_with_parameter'
--- exec
curl -k https://localhost:1994/public%2Fstatus
--- response_body eval
qr/hello1 world/
