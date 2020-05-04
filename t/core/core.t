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
no_long_string();
no_shuffle();
no_root_location();

sub read_file($) {
    my $infile = shift;
    open my $in, $infile
        or die "cannot open $infile for reading: $!";
    my $cert = do { local $/; <$in> };
    close $in;
    $cert;
}

our $yaml_config = read_file("conf/config.yaml");
$yaml_config =~ s/name: APISIX/name: test-gateway/;
$yaml_config =~ s/prefix: \"\/apisix\"/prefix: \"\/test-gateway\"/;

run_tests();

__DATA__

=== TEST 1: the default core name
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.say(core.name)
        }
    }
--- request
GET /t
--- response_body
APISIX
--- no_error_log
[error]



=== TEST 2: custom name
--- yaml_config eval: $::yaml_config
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.say(core.name)
        }
    }
--- request
GET /t
--- response_body
test-gateway
--- error_log
config etcd prefix /test-gateway
--- no_error_log
[error]