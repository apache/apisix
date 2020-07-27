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
$yaml_config =~ s/enable_admin: true/enable_admin: false/;
$yaml_config =~ s/error_log_level: "warn"/error_log_level: "info"/;


$yaml_config .= <<_EOC_;
discovery:
  - etcd
_EOC_

run_tests();

__DATA__

=== TEST 1: set test data
--- config
    location /t {
        content_by_lua_block {
            local etcd = require('apisix.core.etcd')
            etcd.set(discovery_key, { test_service_name = { host = "127.0.0.1", port = 9080} })
        }
    }
--- request
GET /t
--- response_body
done
--- no_error_log
[error]


=== TEST 2: add rount
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "discovery_type": "etcd",
                        "etcd": {
                            "service_name": "test_service_name"
                        },
                        "type": "discovery"
                    },
                    "uri": "/test_etcd"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 3: access
--- request
GET /test_etcd
--- response_body chomp
{"error_msg":"failed to match any routes"}
--- no_error_log
[error]
--- wait: 0.2



