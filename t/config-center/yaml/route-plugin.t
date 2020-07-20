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
$yaml_config =~ s/config_center: etcd/config_center: yaml/;
$yaml_config =~ s/enable_admin: true/enable_admin: false/;

run_tests();

__DATA__

=== TEST 1: route with plugin
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    plugins:
      proxy-rewrite:
        uri: /uri/plugin_proxy_rewrite
        headers:
          X-Api-Version: v2
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /hello
--- more_headers
X-Api-Version:v1
--- response_body
uri: /uri/plugin_proxy_rewrite
host: localhost
x-api-version: v2
x-real-ip: 127.0.0.1
--- no_error_log
[error]


=== TEST 2: route with invalid plugin
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /hello
    plugins:
      proxy-rewrite:
        headers:
          "": ""
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- error_log
failed to check the configuration of plugin proxy-rewrite err: property "headers" validation failed: expect object to have at least 1 properties