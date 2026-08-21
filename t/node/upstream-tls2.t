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
no_long_string();
no_root_location();
no_shuffle();
log_level("info");

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->http_config) {
        my $http_config = <<'_EOC_';

proxy_ssl_trusted_certificate ../../certs/mtls_ca.crt;
proxy_ssl_verify on;

server {
    listen 8767 ssl;
    ssl_certificate ../../certs/mtls_server.crt;
    ssl_certificate_key ../../certs/mtls_server.key;

    location /hello {
        return 200 'ok\n';
    }
}

_EOC_
        $block->set_value("http_config", $http_config);
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
});

run_tests;

__DATA__

=== TEST 1: set tls.verify to true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "scheme": "https",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:8767": 1
                        },
                        "tls": {
                            "verify": true
                        }
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: verification passes for the SNI the certificate is issued for
--- request
GET /hello
--- more_headers
host: admin.apisix.dev
--- response_body
ok



=== TEST 3: verification rejects a certificate that doesn't match the SNI
--- request
GET /hello
--- more_headers
host: invalid.apisix.dev
--- error_code: 502
--- error_log
upstream SSL certificate does not match "invalid.apisix.dev"



=== TEST 4: set tls.verify to false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "methods": ["GET"],
                    "upstream": {
                        "scheme": "https",
                        "type": "roundrobin",
                        "nodes": {
                            "127.0.0.1:8767": 1
                        },
                        "tls": {
                            "verify": false
                        }
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 5: mismatched SNI is accepted once verification is off
--- request
GET /hello
--- more_headers
host: invalid.apisix.dev
--- response_body
ok



=== TEST 6: grpcs upstream is verified by default
--- http2
--- http_config
grpc_ssl_trusted_certificate ../../certs/mtls_ca.crt;
grpc_ssl_verify on;
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /helloworld.Greeter/SayHello
    methods: [
        POST
    ]
    upstream:
      scheme: grpcs
      nodes:
        "127.0.0.1:10052": 1
      type: roundrobin
#END
--- exec
grpcurl -import-path ./t/grpc_server_example/proto -proto helloworld.proto -plaintext -d '{"name":"apisix"}' 127.0.0.1:1984 helloworld.Greeter.SayHello 2>&1 || true
--- error_log
upstream SSL certificate verify error



=== TEST 7: tls.verify survives the internal redirect to @grpc_pass
--- http2
--- http_config
grpc_ssl_trusted_certificate ../../certs/mtls_ca.crt;
grpc_ssl_verify on;
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /helloworld.Greeter/SayHello
    methods: [
        POST
    ]
    upstream:
      scheme: grpcs
      nodes:
        "127.0.0.1:10052": 1
      type: roundrobin
      tls:
        verify: false
#END
--- exec
grpcurl -import-path ./t/grpc_server_example/proto -proto helloworld.proto -plaintext -d '{"name":"apisix"}' 127.0.0.1:1984 helloworld.Greeter.SayHello
--- response_body
{
  "message": "Hello apisix"
}



=== TEST 8: tls.ca_certs survives the internal redirect to @grpc_pass
The upstream serves a certificate that grpc_ssl_trusted_certificate does not
trust, so the request only succeeds if ca_certs reached the handshake.
--- http2
--- http_config
grpc_ssl_trusted_certificate ../../certs/mtls_ca.crt;
grpc_ssl_verify on;
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /helloworld.Greeter/SayHello
    methods: [
        POST
    ]
    upstream:
      scheme: grpcs
      nodes:
        "127.0.0.1:10052": 1
      type: roundrobin
      pass_host: rewrite
      upstream_host: test.com
      tls:
        client_cert: "-----BEGIN CERTIFICATE-----\nMIIDUzCCAjugAwIBAgIURw+Rc5FSNUQWdJD+quORtr9KaE8wDQYJKoZIhvcNAQEN\nBQAwWDELMAkGA1UEBhMCY24xEjAQBgNVBAgMCUd1YW5nRG9uZzEPMA0GA1UEBwwG\nWmh1SGFpMRYwFAYDVQQDDA1jYS5hcGlzaXguZGV2MQwwCgYDVQQLDANvcHMwHhcN\nMjIxMjAxMTAxOTU3WhcNNDIwODE4MTAxOTU3WjBOMQswCQYDVQQGEwJjbjESMBAG\nA1UECAwJR3VhbmdEb25nMQ8wDQYDVQQHDAZaaHVIYWkxGjAYBgNVBAMMEWNsaWVu\ndC5hcGlzaXguZGV2MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzypq\nkrsJ8MaqpS0kr2SboE9aRKOJzd6mY3AZLq3tFpio5cK5oIHkQLfeaaLcd4ycFcZw\nFTpxc+Eth6I0X9on+j4tEibc5IpDnRSAQlzHZzlrOG6WxcOza4VmfcrKqj27oodr\noqXv05r/5yIoRrEN9ZXfA8n2OnjhkP+C3Q68L6dBtPpv+e6HaAuw8MvcsEo+MQwu\ncTZyWqWT2UzKVzToW29dHRW+yZGuYNWRh15X09VSvx+E0s+uYKzN0Cyef2C6VtBJ\nKmJ3NtypAiPqw7Ebfov2Ym/zzU9pyWPi3P1mYPMKQqUT/FpZSXm4iSy0a5qTYhkF\nrFdV1YuYYZL5YGl9aQIDAQABox8wHTAbBgNVHREEFDASghBhZG1pbi5hcGlzaXgu\nZGV2MA0GCSqGSIb3DQEBDQUAA4IBAQBepRpwWdckZ6QdL5EuufYwU7p5SIqkVL/+\nN4/l5YSjPoAZf/M6XkZu/PsLI9/kPZN/PX4oxjZSDH14dU9ON3JjxtSrebizcT8V\naQ13TeW9KSv/i5oT6qBmj+V+RF2YCUhyzXdYokOfsSVtSlA1qMdm+cv0vkjYcImV\nl3L9nVHRPq15dY9sbmWEtFBWvOzqNSuQYax+iYG+XEuL9SPaYlwKRC6eS/dbXa1T\nPPWDQad2X/WmhxPzEHvjSl2bsZF1u0GEdKyhXWMOLCLiYIJo15G7bMz8cTUvkDN3\n6WaWBd6bd2g13Ho/OOceARpkR/ND8PU78Y8cq+zHoOSqH+1aly5H\n-----END CERTIFICATE-----\n"
        client_key: "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEAzypqkrsJ8MaqpS0kr2SboE9aRKOJzd6mY3AZLq3tFpio5cK5\noIHkQLfeaaLcd4ycFcZwFTpxc+Eth6I0X9on+j4tEibc5IpDnRSAQlzHZzlrOG6W\nxcOza4VmfcrKqj27oodroqXv05r/5yIoRrEN9ZXfA8n2OnjhkP+C3Q68L6dBtPpv\n+e6HaAuw8MvcsEo+MQwucTZyWqWT2UzKVzToW29dHRW+yZGuYNWRh15X09VSvx+E\n0s+uYKzN0Cyef2C6VtBJKmJ3NtypAiPqw7Ebfov2Ym/zzU9pyWPi3P1mYPMKQqUT\n/FpZSXm4iSy0a5qTYhkFrFdV1YuYYZL5YGl9aQIDAQABAoIBAD7tUG//lnZnsj/4\nJXONaORaFj5ROrOpFPuRemS+egzqFCuuaXpC2lV6RHnr+XHq6SKII1WfagTb+lt/\nvs760jfmGQSxf1mAUidtqcP+sKc/Pr1mgi/SUTawz8AYEFWD6PHmlqBSLTYml+La\nckd+0pGtk49wEnYSb9n+cv640hra9AYpm9LXUFaypiFEu+xJhtyKKWkmiVGrt/X9\n3aG6MuYeZplW8Xq1L6jcHsieTOB3T+UBfG3O0bELBgTVexOQYI9O4Ejl9/n5/8WP\nAbIw7PaAYc7fBkwOGh7/qYUdHnrm5o9MiRT6dPxrVSf0PZVACmA+JoNjCPv0Typf\n3MMkHoECgYEA9+3LYzdP8j9iv1fP5hn5K6XZAobCD1mnzv3my0KmoSMC26XuS71f\nvyBhjL7zMxGEComvVTF9SaNMfMYTU4CwOJQxLAuT69PEzW6oVEeBoscE5hwhjj6o\n/lr5jMbt807J9HnldSpwllfj7JeiTuqRcCu/cwqKQQ1aB3YBZ7h5pZkCgYEA1ejo\nKrR1hN2FMhp4pj0nZ5+Ry2lyIVbN4kIcoteaPhyQ0AQ0zNoi27EBRnleRwVDYECi\nXAFrgJU+laKsg1iPjvinHibrB9G2p1uv3BEh6lPl9wPFlENTOjPkqjR6eVVZGP8e\nVzxYxIo2x/QLDUeOpxySdG4pdhEHGfvmdGmr2FECgYBeknedzhCR4HnjcTSdmlTA\nwI+p9gt6XYG0ZIewCymSl89UR9RBUeh++HQdgw0z8r+CYYjfH3SiLUdU5R2kIZeW\nzXiAS55OO8Z7cnWFSI17sRz+RcbLAr3l4IAGoi9MO0awGftcGSc/QiFwM1s3bSSz\nPAzYbjHUpKot5Gae0PCeKQKBgQCHfkfRBQ2LY2WDHxFc+0+Ca6jF17zbMUioEIhi\n/X5N6XowyPlI6MM7tRrBsQ7unX7X8Rjmfl/ByschsTDk4avNO+NfTfeBtGymBYWX\nN6Lr8sivdkwoZZzKOSSWSzdos48ELlThnO/9Ti706Lg3aSQK5iY+aakJiC+fXdfT\n1TtsgQKBgQDRYvtK/Cpaq0W6wO3I4R75lHGa7zjEr4HA0Kk/FlwS0YveuTh5xqBj\nwQz2YyuQQfJfJs7kbWOITBT3vuBJ8F+pktL2Xq5p7/ooIXOGS8Ib4/JAS1C/wb+t\nuJHGva12bZ4uizxdL2Q0/n9ziYTiMc/MMh/56o4Je8RMdOMT5lTsRQ==\n-----END RSA PRIVATE KEY-----\n"
        verify: true
        ca_certs:
          - "-----BEGIN CERTIFICATE-----\nMIIEojCCAwqgAwIBAgIJAK253pMhgCkxMA0GCSqGSIb3DQEBCwUAMFYxCzAJBgNV\nBAYTAkNOMRIwEAYDVQQIDAlHdWFuZ0RvbmcxDzANBgNVBAcMBlpodUhhaTEPMA0G\nA1UECgwGaXJlc3R5MREwDwYDVQQDDAh0ZXN0LmNvbTAgFw0xOTA2MjQyMjE4MDVa\nGA8yMTE5MDUzMTIyMTgwNVowVjELMAkGA1UEBhMCQ04xEjAQBgNVBAgMCUd1YW5n\nRG9uZzEPMA0GA1UEBwwGWmh1SGFpMQ8wDQYDVQQKDAZpcmVzdHkxETAPBgNVBAMM\nCHRlc3QuY29tMIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAyCM0rqJe\ncvgnCfOw4fATotPwk5Ba0gC2YvIrO+gSbQkyxXF5jhZB3W6BkWUWR4oNFLLSqcVb\nVDPitz/Mt46Mo8amuS6zTbQetGnBARzPLtmVhJfoeLj0efMiOepOSZflj9Ob4yKR\n2bGdEFOdHPjm+4ggXU9jMKeLqdVvxll/JiVFBW5smPtW1Oc/BV5terhscJdOgmRr\nabf9xiIis9/qVYfyGn52u9452V0owUuwP7nZ01jt6iMWEGeQU6mwPENgvj1olji2\nWjdG2UwpUVp3jp3l7j1ekQ6mI0F7yI+LeHzfUwiyVt1TmtMWn1ztk6FfLRqwJWR/\nEvm95vnfS3Le4S2ky3XAgn2UnCMyej3wDN6qHR1onpRVeXhrBajbCRDRBMwaNw/1\n/3Uvza8QKK10PzQR6OcQ0xo9psMkd9j9ts/dTuo2fzaqpIfyUbPST4GdqNG9NyIh\n/B9g26/0EWcjyO7mYVkaycrtLMaXm1u9jyRmcQQI1cGrGwyXbrieNp63AgMBAAGj\ncTBvMB0GA1UdDgQWBBSZtSvV8mBwl0bpkvFtgyiOUUcbszAfBgNVHSMEGDAWgBSZ\ntSvV8mBwl0bpkvFtgyiOUUcbszAMBgNVHRMEBTADAQH/MB8GA1UdEQQYMBaCCHRl\nc3QuY29tggoqLnRlc3QuY29tMA0GCSqGSIb3DQEBCwUAA4IBgQAHGEul/x7ViVgC\ntC8CbXEslYEkj1XVr2Y4hXZXAXKd3W7V3TC8rqWWBbr6L/tsSVFt126V5WyRmOaY\n1A5pju8VhnkhYxYfZALQxJN2tZPFVeME9iGJ9BE1wPtpMgITX8Rt9kbNlENfAgOl\nPYzrUZN1YUQjX+X8t8/1VkSmyZysr6ngJ46/M8F16gfYXc9zFj846Z9VST0zCKob\nrJs3GtHOkS9zGGldqKKCj+Awl0jvTstI4qtS1ED92tcnJh5j/SSXCAB5FgnpKZWy\nhme45nBQj86rJ8FhN+/aQ9H9/2Ib6Q4wbpaIvf4lQdLUEcWAeZGW6Rk0JURwEog1\n7/mMgkapDglgeFx9f/XztSTrkHTaX4Obr+nYrZ2V4KOB4llZnK5GeNjDrOOJDk2y\nIJFgBOZJWyS93dQfuKEj42hA79MuX64lMSCVQSjX+ipR289GQZqFrIhiJxLyA+Ve\nU/OOcSRr39Kuis/JJ+DkgHYa/PWHZhnJQBxcqXXk1bJGw9BNbhM=\n-----END CERTIFICATE-----\n"
#END
--- exec
grpcurl -import-path ./t/grpc_server_example/proto -proto helloworld.proto -plaintext -d '{"name":"apisix"}' 127.0.0.1:1984 helloworld.Greeter.SayHello
--- response_body
{
  "message": "Hello apisix"
}
