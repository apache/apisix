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
$yaml_config =~ s/enable_heartbeat: true/enable_heartbeat: false/;
$yaml_config =~ s/config_center: etcd/config_center: yaml/;
$yaml_config =~ s/enable_admin: true/enable_admin: false/;

run_tests();

__DATA__

=== TEST 1: hit route
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
    -
        uri: /hello
        upstream_id: 1
upstreams:
    -
        id: 1
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 2: not found upstream
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
    -
        uri: /hello
        upstream_id: 1111
upstreams:
    -
        id: 1
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
--- request
GET /hello
--- error_code: 502
--- error_log
failed to find upstream by id: 1111


=== TEST 3: upstream_id priority upstream
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
    -
        uri: /hello
        upstream_id: 1
        upstream:
            nodes:
                "127.0.0.1:1977": 1
            type: roundrobin
upstreams:
    -
        id: 1
        nodes:
            "127.0.0.1:1981": 1
        type: roundrobin
#END
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]
