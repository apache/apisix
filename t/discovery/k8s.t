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

BEGIN {
    $ENV{KUBERNETES_SERVICE_HOST} = "127.0.0.1";
    $ENV{KUBERNETES_SERVICE_PORT} = "6443";

    my $token_var_file = "/var/run/secrets/kubernetes.io/serviceaccount/token";
    my $token_from_var = eval { `cat ${token_var_file} 2>/dev/null` };
    if ($token_from_var){
      $ENV{KUBERNETES_TOKEN_IN_VAR}="true";
      $ENV{KUBERNETES_CLIENT_TOKEN}=$token_from_var;
      $ENV{KUBERNETES_CLIENT_TOKEN_FILE}=$token_var_file;
    }else {
      my $token_tmp_file = "/tmp/var/run/secrets/kubernetes.io/serviceaccount/token";
      my $token_from_tmp = eval { `cat ${token_tmp_file} 2>/dev/null` };
      if ($token_from_tmp) {
        $ENV{KUBERNETES_TOKEN_IN_TMP}="true";
        $ENV{KUBERNETES_CLIENT_TOKEN}=$token_from_tmp;
        $ENV{KUBERNETES_CLIENT_TOKEN_FILE}=$token_tmp_file;
      }
    }
}

use t::APISIX 'no_plan';

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();
workers(4);

add_block_preprocessor(sub {
    my ($block) = @_;

    my $token_in_var = eval { `echo -n \$KUBERNETES_TOKEN_IN_VAR 2>/dev/null` };
    my $token_in_tmp = eval { `echo -n \$KUBERNETES_TOKEN_IN_TMP 2>/dev/null` };

    my $yaml_config = $block->yaml_config // <<_EOC_;
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
_EOC_

    if ($token_in_var eq "true") {
       $yaml_config .= <<_EOC_;
discovery:
  k8s: {}
_EOC_
    }

    if ($token_in_tmp eq "true") {
       $yaml_config .= <<_EOC_;
discovery:
  k8s:
    client:
      token_file: /tmp/var/run/secrets/kubernetes.io/serviceaccount/token
_EOC_
    }

    $block->set_value("yaml_config", $yaml_config);

    my $apisix_yaml = $block->apisix_yaml // <<_EOC_;
routes: []
#END
_EOC_

    $block->set_value("apisix_yaml", $apisix_yaml);

    my $main_config = $block->main_config // <<_EOC_;
env KUBERNETES_SERVICE_HOST;
env KUBERNETES_SERVICE_PORT;
env KUBERNETES_CLIENT_TOKEN;
env KUBERNETES_CLIENT_TOKEN_FILE;
_EOC_

    $block->set_value("main_config", $main_config);

    my $config = $block->config  // <<_EOC_;
        location /t {
            content_by_lua_block {
              local d = require("apisix.discovery.k8s")
              ngx.sleep(1)
              local s = ngx.var.arg_s
              local nodes = d.nodes(s)

              ngx.status = 200
              local body

              if nodes == nil or #nodes == 0 then
                body="empty"
              else
                body="passed"
              end
              ngx.say(body)
            }
        }
_EOC_

    $block->set_value("config", $config);
});

run_tests();

__DATA__

=== TEST 1: use default parameters
--- request
GET /t?s=default/kubernetes:https
--- response_body
passed



=== TEST 2: use specify parameters
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
discovery:
  k8s:
    service:
      host: "127.0.0.1"
      port: "6443"
    client:
      token: "${KUBERNETES_CLIENT_TOKEN}"
nginx_config:
  envs:
  - KUBERNETES_CLIENT_TOKEN
--- request
GET /t?s=default/kubernetes:https
--- response_body
passed
--- no_error_log
[error]



=== TEST 3: use specify environment parameters
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
discovery:
  k8s:
    service:
      host: ${KUBERNETES_SERVICE_HOST}
      port: ${KUBERNETES_SERVICE_PORT}
    client:
      token: ${KUBERNETES_CLIENT_TOKEN}
nginx_config:
  envs:
  - KUBERNETES_SERVICE_HOST
  - KUBERNETES_SERVICE_PORT
  - KUBERNETES_CLIENT_TOKEN
--- request
GET /t?s=default/kubernetes:https
--- response_body
passed
--- no_error_log
[error]



=== TEST 4: use token_file
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
discovery:
  k8s:
    client:
      token_file: ${KUBERNETES_CLIENT_TOKEN_FILE}
nginx_config:
  envs:
  - KUBERNETES_SERVICE_HOST
  - KUBERNETES_SERVICE_PORT
  - KUBERNETES_CLIENT_TOKEN_FILE
--- request
GET /t?s=default/kubernetes:https
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: use http
--- yaml_config
apisix:
  node_listen: 1984
  config_center: yaml
  enable_admin: false
discovery:
  k8s:
    service:
      schema: http
      host: "127.0.0.1"
      port: "6445"
    client:
      token: ""
--- request
GET /t?s=default/kubernetes:https
--- response_body
passed
--- no_error_log
[error]



=== TEST 6: error service_name  - bad namespace
--- request
GET /t?s=notexist/kubernetes:https
--- response_body
empty
--- no_error_log
[error]



=== TEST 7: error service_name   - bad service
--- request
GET /t?s=default/notexist:https
--- response_body
empty
--- no_error_log
[error]



=== TEST 8: error service_name   - bad port
--- request
GET /t?s=default/kubernetes:notexist
--- response_body
empty
--- no_error_log
[error]
