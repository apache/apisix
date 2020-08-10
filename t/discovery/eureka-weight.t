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
$yaml_config =~ s/enable_admin: true/enable_admin: false/;
$yaml_config =~ s/  discovery:/  discovery: eureka #/;
$yaml_config =~ s/#  discovery:/  discovery: eureka #/;
$yaml_config =~ s/error_log_level: "warn"/error_log_level: "info"/;
$yaml_config =~ s/enable_debug: false/enable_debug: true/;


$yaml_config .= <<_EOC_;
eureka:
 host:
   - "http://127.0.0.1:8761"
 prefix: "/eureka/"
 fetch_interval: 1
 weight: 100
 timeout:
   connect: 1500
   send: 1500
   read: 1500
_EOC_

run_tests();

__DATA__

=== TEST 1: registry APISIX-EUREKA-USER-SERVICE
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:8761/eureka/apps/APISIX-EUREKA-USER-SERVICE"
            local httpc = http.new()
            local res, err = httpc:request_uri(uri, {
                         method = "POST",
                         body="{\"instance\":{\"instanceId\":\"one\",\"app\":\"APISIX-EUREKA-USER-SERVICE\",\"ipAddr\":\"127.0.0.1\",\"port\":{\"$\":1980,\"@enabled\":\"true\"},\"dataCenterInfo\":{\"@class\":\"com.netflix.appinfo.InstanceInfo$DefaultDataCenterInfo\",\"name\":\"MyOwn\"},\"hostName\":\"instance0.application0.com\",\"status\":\"UP\",\"metadata\":{\"weight\":\"20\"},\"overriddenStatus\":\"UNKNOWN\"}}",
                        headers={["Content-Type"] = "application/json",}
              })
            if not res then
                ngx.say(err)
                return
            end
            res, err = httpc:request_uri(uri, {
                    method = "POST",
                    body="{\"instance\":{\"instanceId\":\"two\",\"app\":\"APISIX-EUREKA-USER-SERVICE\",\"ipAddr\":\"127.0.0.1\",\"port\":{\"$\":1981,\"@enabled\":\"true\"},\"dataCenterInfo\":{\"@class\":\"com.netflix.appinfo.InstanceInfo$DefaultDataCenterInfo\",\"name\":\"MyOwn\"},\"hostName\":\"instance0.application0.com\",\"status\":\"UP\",\"metadata\":{\"weight\":\"80\"},\"overriddenStatus\":\"UNKNOWN\"}}",
                    headers={["Content-Type"] = "application/json",}
              })
            if not res then
                ngx.say(err)
                return
            end
        }
    }
--- request
GET /t
--- response_body
--- no_error_log
[error]



=== TEST 2: get APISIX-EUREKA-USER-SERVICE info from EUREKA
--- yaml_config eval: $::yaml_config
--- apisix_yaml
routes:
  -
    uri: /eureka-weight/*
    plugins:
      proxy-rewrite:
        regex_uri: ["^/eureka-weight/(.*)", "/${1}"]
    upstream:
      service_name: APISIX-EUREKA-USER-SERVICE
      type: roundrobin
#END
--- request
GET /eureka-weight/hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 3: hit routes
--- config
    location /t {
        content_by_lua_block {
            local http = require "resty.http"
            local uri = "http://127.0.0.1:" .. ngx.var.server_port
                        .. "/eureka-weight/server_port"

            local ports_count = {}
            for i = 1, 10 do
                local httpc = http.new()
                local res, err = httpc:request_uri(uri, {method = "GET"})
                if not res then
                    ngx.say(err)
                    return
                end
                ports_count[res.body] = (ports_count[res.body] or 0) + 1
            end

            local ports_arr = {}
            for port, count in pairs(ports_count) do
                table.insert(ports_arr, {port = port, count = count})
            end

            local function cmd(a, b)
                return a.port > b.port
            end
            table.sort(ports_arr, cmd)

            ngx.say(require("cjson").encode(ports_arr))
            ngx.exit(200)
        }
    }
--- request
GET /t
--- yaml_config eval: $::yaml_config
--- response_body
[{"count":8,"port":"1981"},{"count":2,"port":"1980"}]
--- no_error_log
[error]













