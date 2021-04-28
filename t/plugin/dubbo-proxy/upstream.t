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

if ($version !~ m/\/mod_dubbo/) {
    plan(skip_all => "mod_dubbo not installed");
} else {
    plan('no_plan');
}

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();
worker_connections(256);

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /hello");
    }

    if (!defined $block->disable_dubbo) {
        my $extra_yaml_config = <<_EOC_;
plugins:
    - dubbo-proxy
_EOC_

        $block->set_value("extra_yaml_config", $extra_yaml_config);
    }

    my $yaml_config = $block->yaml_config // <<_EOC_;
apisix:
    node_listen: 1984
    config_center: yaml
    enable_admin: false
_EOC_

    $block->set_value("yaml_config", $yaml_config);
});

run_tests();

__DATA__

=== TEST 1: retry
--- apisix_yaml
upstreams:
    - nodes:
        - host: 127.0.0.1
          port: 20881
          weight: 1
        - host: 127.0.0.1
          port: 20880
          weight: 1
      type: roundrobin
      id: 1
routes:
  -
    uri: /hello
    plugins:
        dubbo-proxy:
            service_name: org.apache.dubbo.backend.DemoService
            service_version: 0.0.0
            method: hello
    upstream_id: 1
#END
--- response_body
dubbo success



=== TEST 2: upstream return error
--- apisix_yaml
routes:
  -
    uri: /hello
    plugins:
        dubbo-proxy:
            service_name: org.apache.dubbo.backend.DemoService
            service_version: 0.0.0
            method: fail
    upstream_id: 1
upstreams:
  - nodes:
        "127.0.0.1:20880": 1
    type: roundrobin
    id: 1
#END
--- response_body
dubbo fail
--- error_code: 503



=== TEST 3: upstream timeout
--- apisix_yaml
routes:
  -
    uri: /hello
    plugins:
        dubbo-proxy:
            service_name: org.apache.dubbo.backend.DemoService
            service_version: 0.0.0
            method: timeout
    upstream_id: 1
upstreams:
  - nodes:
        "127.0.0.1:20880": 1
    type: roundrobin
    timeout:
        connect: 0.1
        read: 0.1
        send: 0.1
    id: 1
#END
--- error_log
upstream timed out
--- error_code: 504



=== TEST 4: upstream return non-string status code
--- apisix_yaml
routes:
  -
    uri: /hello
    plugins:
        dubbo-proxy:
            service_name: org.apache.dubbo.backend.DemoService
            service_version: 0.0.0
            method: badStatus
    upstream_id: 1
upstreams:
  - nodes:
        "127.0.0.1:20880": 1
    type: roundrobin
    id: 1
#END
--- response_body
ok
