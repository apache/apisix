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
$yaml_config =~ s/enable_admin: true/enable_admin: false/;
$yaml_config =~ s/  discovery:/  discovery: eureka #/;
$yaml_config =~ s/#  discovery:/  discovery: eureka #/;

$yaml_config .= <<_EOC_;
eureka:
 host:
   - "http://127.0.0.1:8761"
 prefix: "/eureka/"
 weight: 100
 timeout:
   connect: 2000
   send: 2000
   read: 5000
_EOC_

run_tests();

__DATA__


=== TEST 1: get APISIX-EUREKA info from EUREKA
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /eureka/*
    upstream:
      service_name: APISIX-EUREKA
      type: roundrobin

#END
--- request
GET /eureka/apps/APISIX-EUREKA
--- response_body_like
.*<name>APISIX-EUREKA</name>.*
--- error_log
use config_center: yaml
--- no_error_log
[error]


