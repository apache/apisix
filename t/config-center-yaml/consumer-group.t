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

add_block_preprocessor(sub {
    my ($block) = @_;

    my $yaml_config = $block->yaml_config // <<_EOC_;
apisix:
    node_listen: 1984
deployment:
    role: data_plane
    role_data_plane:
        config_provider: yaml
_EOC_

    $block->set_value("yaml_config", $yaml_config);

    my $routes = <<_EOC_;
routes:
  -
    uri: /hello
    plugins:
        key-auth:
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
_EOC_

    $block->set_value("apisix_yaml", $block->apisix_yaml . $routes);

    if (!$block->request) {
        $block->set_value("request", "GET /hello?apikey=one");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: sanity
--- apisix_yaml
consumer_groups:
    - id: foobar
      plugins:
          response-rewrite:
              body: "hello\n"
consumers:
    - username: one
      group_id: foobar
      plugins:
          key-auth:
              key: one
#END
--- response_body
hello



=== TEST 2: consumer group not found
--- apisix_yaml
consumers:
   - username: one
     group_id: invalid_group
     plugins:
       key-auth:
         key: one
#END
--- error_code: 503
--- error_log
failed to fetch consumer group config by id: invalid_group



=== TEST 3: plugin priority
--- apisix_yaml
consumer_groups:
    - id: foobar
      plugins:
        response-rewrite:
          body: "hello\n"
consumers:
  - username: one
    group_id: foobar
    plugins:
      key-auth:
        key: one
      response-rewrite:
        body: "world\n"
#END
--- response_body
world



=== TEST 4: invalid plugin
--- apisix_yaml
consumer_groups:
    - id: foobar
      plugins:
        example-plugin:
          skey: "s"
        response-rewrite:
          body: "hello\n"
consumers:
  - username: one
    group_id: foobar
    plugins:
      key-auth:
        key: one
#END
--- error_code: 503
--- error_log
failed to check the configuration of plugin example-plugin
failed to fetch consumer group config by id: foobar
