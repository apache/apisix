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

    if (!$block->request) {
        $block->set_value("request", "GET /hello");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests();

__DATA__

=== TEST 1: sanity
--- apisix_json
{
  "routes": [
    {
      "id": 1,
      "uri": "/hello",
      "upstream": {
        "nodes": {
          "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
      }
    }
  ],
  "global_rules": [
    {
      "id": 1,
      "plugins": {
        "response-rewrite": {
          "body": "hello\n"
        }
      }
    }
  ]
}
--- response_body
hello



=== TEST 2: global rule with bad plugin
--- apisix_json
{
  "routes": [
    {
      "id": 1,
      "uri": "/hello",
      "upstream": {
        "nodes": {
          "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
      }
    }
  ],
  "global_rules": [
    {
      "id": 1,
      "plugins": {
        "response-rewrite": {
          "body": 4
        }
      }
    }
  ]
}
--- response_body
hello world
--- error_log
property "body" validation failed



=== TEST 3: fix global rule with default value
--- apisix_json
{
  "routes": [
    {
      "id": 1,
      "uri": "/hello",
      "upstream": {
        "nodes": {
          "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
      }
    }
  ],
  "global_rules": [
    {
      "id": 1,
      "plugins": {
        "uri-blocker": {
          "block_rules": [
            "/h*"
          ]
        }
      }
    }
  ]
}
--- error_code: 403



=== TEST 4: common phase without matched route
--- apisix_json
{
  "routes": [
    {
      "uri": "/apisix/prometheus/metrics",
      "plugins": {
        "public-api": {}
      }
    }
  ],
  "global_rules": [
    {
      "id": 1,
      "plugins": {
        "cors": {
          "allow_origins": "http://a.com,http://b.com"
        }
      }
    }
  ]
}
--- request
GET /apisix/prometheus/metrics
--- error_code: 200
