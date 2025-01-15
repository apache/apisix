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

no_long_string();
no_root_location();
no_shuffle();
add_block_preprocessor(sub {
    my ($block) = @_;
    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }
    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: Unary API grpcs proxy test with mTLS
--- http2
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
      tls:
        client_cert: "-----BEGIN CERTIFICATE-----\nMIIDUzCCAjugAwIBAgIURw+Rc5FSNUQWdJD+quORtr9KaE8wDQYJKoZIhvcNAQEN\nBQAwWDELMAkGA1UEBhMCY24xEjAQBgNVBAgMCUd1YW5nRG9uZzEPMA0GA1UEBwwG\nWmh1SGFpMRYwFAYDVQQDDA1jYS5hcGlzaXguZGV2MQwwCgYDVQQLDANvcHMwHhcN\nMjIxMjAxMTAxOTU3WhcNNDIwODE4MTAxOTU3WjBOMQswCQYDVQQGEwJjbjESMBAG\nA1UECAwJR3VhbmdEb25nMQ8wDQYDVQQHDAZaaHVIYWkxGjAYBgNVBAMMEWNsaWVu\ndC5hcGlzaXguZGV2MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzypq\nkrsJ8MaqpS0kr2SboE9aRKOJzd6mY3AZLq3tFpio5cK5oIHkQLfeaaLcd4ycFcZw\nFTpxc+Eth6I0X9on+j4tEibc5IpDnRSAQlzHZzlrOG6WxcOza4VmfcrKqj27oodr\noqXv05r/5yIoRrEN9ZXfA8n2OnjhkP+C3Q68L6dBtPpv+e6HaAuw8MvcsEo+MQwu\ncTZyWqWT2UzKVzToW29dHRW+yZGuYNWRh15X09VSvx+E0s+uYKzN0Cyef2C6VtBJ\nKmJ3NtypAiPqw7Ebfov2Ym/zzU9pyWPi3P1mYPMKQqUT/FpZSXm4iSy0a5qTYhkF\nrFdV1YuYYZL5YGl9aQIDAQABox8wHTAbBgNVHREEFDASghBhZG1pbi5hcGlzaXgu\nZGV2MA0GCSqGSIb3DQEBDQUAA4IBAQBepRpwWdckZ6QdL5EuufYwU7p5SIqkVL/+\nN4/l5YSjPoAZf/M6XkZu/PsLI9/kPZN/PX4oxjZSDH14dU9ON3JjxtSrebizcT8V\naQ13TeW9KSv/i5oT6qBmj+V+RF2YCUhyzXdYokOfsSVtSlA1qMdm+cv0vkjYcImV\nl3L9nVHRPq15dY9sbmWEtFBWvOzqNSuQYax+iYG+XEuL9SPaYlwKRC6eS/dbXa1T\nPPWDQad2X/WmhxPzEHvjSl2bsZF1u0GEdKyhXWMOLCLiYIJo15G7bMz8cTUvkDN3\n6WaWBd6bd2g13Ho/OOceARpkR/ND8PU78Y8cq+zHoOSqH+1aly5H\n-----END CERTIFICATE-----\n"
        client_key: "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEAzypqkrsJ8MaqpS0kr2SboE9aRKOJzd6mY3AZLq3tFpio5cK5\noIHkQLfeaaLcd4ycFcZwFTpxc+Eth6I0X9on+j4tEibc5IpDnRSAQlzHZzlrOG6W\nxcOza4VmfcrKqj27oodroqXv05r/5yIoRrEN9ZXfA8n2OnjhkP+C3Q68L6dBtPpv\n+e6HaAuw8MvcsEo+MQwucTZyWqWT2UzKVzToW29dHRW+yZGuYNWRh15X09VSvx+E\n0s+uYKzN0Cyef2C6VtBJKmJ3NtypAiPqw7Ebfov2Ym/zzU9pyWPi3P1mYPMKQqUT\n/FpZSXm4iSy0a5qTYhkFrFdV1YuYYZL5YGl9aQIDAQABAoIBAD7tUG//lnZnsj/4\nJXONaORaFj5ROrOpFPuRemS+egzqFCuuaXpC2lV6RHnr+XHq6SKII1WfagTb+lt/\nvs760jfmGQSxf1mAUidtqcP+sKc/Pr1mgi/SUTawz8AYEFWD6PHmlqBSLTYml+La\nckd+0pGtk49wEnYSb9n+cv640hra9AYpm9LXUFaypiFEu+xJhtyKKWkmiVGrt/X9\n3aG6MuYeZplW8Xq1L6jcHsieTOB3T+UBfG3O0bELBgTVexOQYI9O4Ejl9/n5/8WP\nAbIw7PaAYc7fBkwOGh7/qYUdHnrm5o9MiRT6dPxrVSf0PZVACmA+JoNjCPv0Typf\n3MMkHoECgYEA9+3LYzdP8j9iv1fP5hn5K6XZAobCD1mnzv3my0KmoSMC26XuS71f\nvyBhjL7zMxGEComvVTF9SaNMfMYTU4CwOJQxLAuT69PEzW6oVEeBoscE5hwhjj6o\n/lr5jMbt807J9HnldSpwllfj7JeiTuqRcCu/cwqKQQ1aB3YBZ7h5pZkCgYEA1ejo\nKrR1hN2FMhp4pj0nZ5+Ry2lyIVbN4kIcoteaPhyQ0AQ0zNoi27EBRnleRwVDYECi\nXAFrgJU+laKsg1iPjvinHibrB9G2p1uv3BEh6lPl9wPFlENTOjPkqjR6eVVZGP8e\nVzxYxIo2x/QLDUeOpxySdG4pdhEHGfvmdGmr2FECgYBeknedzhCR4HnjcTSdmlTA\nwI+p9gt6XYG0ZIewCymSl89UR9RBUeh++HQdgw0z8r+CYYjfH3SiLUdU5R2kIZeW\nzXiAS55OO8Z7cnWFSI17sRz+RcbLAr3l4IAGoi9MO0awGftcGSc/QiFwM1s3bSSz\nPAzYbjHUpKot5Gae0PCeKQKBgQCHfkfRBQ2LY2WDHxFc+0+Ca6jF17zbMUioEIhi\n/X5N6XowyPlI6MM7tRrBsQ7unX7X8Rjmfl/ByschsTDk4avNO+NfTfeBtGymBYWX\nN6Lr8sivdkwoZZzKOSSWSzdos48ELlThnO/9Ti706Lg3aSQK5iY+aakJiC+fXdfT\n1TtsgQKBgQDRYvtK/Cpaq0W6wO3I4R75lHGa7zjEr4HA0Kk/FlwS0YveuTh5xqBj\nwQz2YyuQQfJfJs7kbWOITBT3vuBJ8F+pktL2Xq5p7/ooIXOGS8Ib4/JAS1C/wb+t\nuJHGva12bZ4uizxdL2Q0/n9ziYTiMc/MMh/56o4Je8RMdOMT5lTsRQ==\n-----END RSA PRIVATE KEY-----\n"
      nodes:
        "127.0.0.1:10053": 1
      type: roundrobin
#END
--- exec
grpcurl -import-path ./t/grpc_server_example/proto -proto helloworld.proto -plaintext -d '{"name":"apisix"}' 127.0.0.1:1984 helloworld.Greeter.SayHello
--- response_body
{
  "message": "Hello apisix"
}



=== TEST 2: Bidirectional API grpcs proxy test with mTLS
--- http2
--- apisix_yaml
routes:
  -
    id: 1
    uris:
        - /helloworld.Greeter/SayHelloBidirectionalStream
    methods: [
        POST
    ]
    upstream:
      scheme: grpcs
      tls:
        client_cert: "-----BEGIN CERTIFICATE-----\nMIIDUzCCAjugAwIBAgIURw+Rc5FSNUQWdJD+quORtr9KaE8wDQYJKoZIhvcNAQEN\nBQAwWDELMAkGA1UEBhMCY24xEjAQBgNVBAgMCUd1YW5nRG9uZzEPMA0GA1UEBwwG\nWmh1SGFpMRYwFAYDVQQDDA1jYS5hcGlzaXguZGV2MQwwCgYDVQQLDANvcHMwHhcN\nMjIxMjAxMTAxOTU3WhcNNDIwODE4MTAxOTU3WjBOMQswCQYDVQQGEwJjbjESMBAG\nA1UECAwJR3VhbmdEb25nMQ8wDQYDVQQHDAZaaHVIYWkxGjAYBgNVBAMMEWNsaWVu\ndC5hcGlzaXguZGV2MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzypq\nkrsJ8MaqpS0kr2SboE9aRKOJzd6mY3AZLq3tFpio5cK5oIHkQLfeaaLcd4ycFcZw\nFTpxc+Eth6I0X9on+j4tEibc5IpDnRSAQlzHZzlrOG6WxcOza4VmfcrKqj27oodr\noqXv05r/5yIoRrEN9ZXfA8n2OnjhkP+C3Q68L6dBtPpv+e6HaAuw8MvcsEo+MQwu\ncTZyWqWT2UzKVzToW29dHRW+yZGuYNWRh15X09VSvx+E0s+uYKzN0Cyef2C6VtBJ\nKmJ3NtypAiPqw7Ebfov2Ym/zzU9pyWPi3P1mYPMKQqUT/FpZSXm4iSy0a5qTYhkF\nrFdV1YuYYZL5YGl9aQIDAQABox8wHTAbBgNVHREEFDASghBhZG1pbi5hcGlzaXgu\nZGV2MA0GCSqGSIb3DQEBDQUAA4IBAQBepRpwWdckZ6QdL5EuufYwU7p5SIqkVL/+\nN4/l5YSjPoAZf/M6XkZu/PsLI9/kPZN/PX4oxjZSDH14dU9ON3JjxtSrebizcT8V\naQ13TeW9KSv/i5oT6qBmj+V+RF2YCUhyzXdYokOfsSVtSlA1qMdm+cv0vkjYcImV\nl3L9nVHRPq15dY9sbmWEtFBWvOzqNSuQYax+iYG+XEuL9SPaYlwKRC6eS/dbXa1T\nPPWDQad2X/WmhxPzEHvjSl2bsZF1u0GEdKyhXWMOLCLiYIJo15G7bMz8cTUvkDN3\n6WaWBd6bd2g13Ho/OOceARpkR/ND8PU78Y8cq+zHoOSqH+1aly5H\n-----END CERTIFICATE-----\n"
        client_key: "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEAzypqkrsJ8MaqpS0kr2SboE9aRKOJzd6mY3AZLq3tFpio5cK5\noIHkQLfeaaLcd4ycFcZwFTpxc+Eth6I0X9on+j4tEibc5IpDnRSAQlzHZzlrOG6W\nxcOza4VmfcrKqj27oodroqXv05r/5yIoRrEN9ZXfA8n2OnjhkP+C3Q68L6dBtPpv\n+e6HaAuw8MvcsEo+MQwucTZyWqWT2UzKVzToW29dHRW+yZGuYNWRh15X09VSvx+E\n0s+uYKzN0Cyef2C6VtBJKmJ3NtypAiPqw7Ebfov2Ym/zzU9pyWPi3P1mYPMKQqUT\n/FpZSXm4iSy0a5qTYhkFrFdV1YuYYZL5YGl9aQIDAQABAoIBAD7tUG//lnZnsj/4\nJXONaORaFj5ROrOpFPuRemS+egzqFCuuaXpC2lV6RHnr+XHq6SKII1WfagTb+lt/\nvs760jfmGQSxf1mAUidtqcP+sKc/Pr1mgi/SUTawz8AYEFWD6PHmlqBSLTYml+La\nckd+0pGtk49wEnYSb9n+cv640hra9AYpm9LXUFaypiFEu+xJhtyKKWkmiVGrt/X9\n3aG6MuYeZplW8Xq1L6jcHsieTOB3T+UBfG3O0bELBgTVexOQYI9O4Ejl9/n5/8WP\nAbIw7PaAYc7fBkwOGh7/qYUdHnrm5o9MiRT6dPxrVSf0PZVACmA+JoNjCPv0Typf\n3MMkHoECgYEA9+3LYzdP8j9iv1fP5hn5K6XZAobCD1mnzv3my0KmoSMC26XuS71f\nvyBhjL7zMxGEComvVTF9SaNMfMYTU4CwOJQxLAuT69PEzW6oVEeBoscE5hwhjj6o\n/lr5jMbt807J9HnldSpwllfj7JeiTuqRcCu/cwqKQQ1aB3YBZ7h5pZkCgYEA1ejo\nKrR1hN2FMhp4pj0nZ5+Ry2lyIVbN4kIcoteaPhyQ0AQ0zNoi27EBRnleRwVDYECi\nXAFrgJU+laKsg1iPjvinHibrB9G2p1uv3BEh6lPl9wPFlENTOjPkqjR6eVVZGP8e\nVzxYxIo2x/QLDUeOpxySdG4pdhEHGfvmdGmr2FECgYBeknedzhCR4HnjcTSdmlTA\nwI+p9gt6XYG0ZIewCymSl89UR9RBUeh++HQdgw0z8r+CYYjfH3SiLUdU5R2kIZeW\nzXiAS55OO8Z7cnWFSI17sRz+RcbLAr3l4IAGoi9MO0awGftcGSc/QiFwM1s3bSSz\nPAzYbjHUpKot5Gae0PCeKQKBgQCHfkfRBQ2LY2WDHxFc+0+Ca6jF17zbMUioEIhi\n/X5N6XowyPlI6MM7tRrBsQ7unX7X8Rjmfl/ByschsTDk4avNO+NfTfeBtGymBYWX\nN6Lr8sivdkwoZZzKOSSWSzdos48ELlThnO/9Ti706Lg3aSQK5iY+aakJiC+fXdfT\n1TtsgQKBgQDRYvtK/Cpaq0W6wO3I4R75lHGa7zjEr4HA0Kk/FlwS0YveuTh5xqBj\nwQz2YyuQQfJfJs7kbWOITBT3vuBJ8F+pktL2Xq5p7/ooIXOGS8Ib4/JAS1C/wb+t\nuJHGva12bZ4uizxdL2Q0/n9ziYTiMc/MMh/56o4Je8RMdOMT5lTsRQ==\n-----END RSA PRIVATE KEY-----\n"
      nodes:
        "127.0.0.1:10053": 1
      type: roundrobin
#END
--- exec
grpcurl -import-path ./t/grpc_server_example/proto -proto helloworld.proto -plaintext -d '{"name":"apisix"}' 127.0.0.1:1984 helloworld.Greeter.SayHelloBidirectionalStream
--- response_body
{
  "message": "Hello apisix"
}
{
  "message": "stream ended"
}
