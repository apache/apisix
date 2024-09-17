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

$ENV{SOME_STRING_VALUE_BUT_DIFFERENT} = 'astringvaluebutdifferent';
$ENV{SOME_STRING_VALUE} = 'astringvalue';

our $yaml_config = <<_EOC_;
apisix:
  node_listen: 1984
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
_EOC_

our $apisix_yaml = <<_EOC_;
upstreams:
  - id: 1
    nodes:
      - host: 127.0.0.1
        port: 1980
        weight: 1
routes:
  - uri: /hello
    upstream_id: 1
    plugins:
      response-rewrite:
        headers:
          set:
            X-Some-String-Value-But-Different: Different \${{SOME_STRING_VALUE_BUT_DIFFERENT}}
            X-Some-String-Value: \${{SOME_STRING_VALUE}}
#END
_EOC_

our $response_headers_correct = <<_EOC_;
X-Some-String-Value-But-Different: Different astringvaluebutdifferent
X-Some-String-Value: astringvalue
_EOC_

our $response_headers_INCORRECT = <<_EOC_;
X-Some-String-Value-But-Different: Different astringvalue
X-Some-String-Value: astringvalue
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /hello");
    }
});

run_tests();

__DATA__

=== TEST 1: assignment style, the PREFIX 1st - incorrect
--- main_config
env SOME_STRING_VALUE=astringvalue;
env SOME_STRING_VALUE_BUT_DIFFERENT=astringvaluebutdifferent;
--- yaml_config eval: $::yaml_config
--- apisix_yaml eval: $::apisix_yaml
--- response_headers eval: $::response_headers_INCORRECT



=== TEST 2: assignment style, the DIFF 1st - correct
--- main_config
env SOME_STRING_VALUE_BUT_DIFFERENT=astringvaluebutdifferent;
env SOME_STRING_VALUE=astringvalue;
--- yaml_config eval: $::yaml_config
--- apisix_yaml eval: $::apisix_yaml
--- response_headers eval: $::response_headers_correct



=== TEST 3: declaration style, the PREFIX 1st - correct
--- main_config
env SOME_STRING_VALUE;
env SOME_STRING_VALUE_BUT_DIFFERENT;
--- yaml_config eval: $::yaml_config
--- apisix_yaml eval: $::apisix_yaml
--- response_headers eval: $::response_headers_correct



=== TEST 4: declaration style, the DIFF 1st - also correct
--- main_config
env SOME_STRING_VALUE_BUT_DIFFERENT;
env SOME_STRING_VALUE;
--- yaml_config eval: $::yaml_config
--- apisix_yaml eval: $::apisix_yaml
--- response_headers eval: $::response_headers_correct
