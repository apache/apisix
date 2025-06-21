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

    $block->set_value("stream_enable", 1);

    if (!$block->stream_request) {
        $block->set_value("stream_request", "mmm");
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
  "stream_routes": [
    {
      "server_addr": "127.0.0.1",
      "server_port": 1985,
      "id": 1,
      "upstream": {
        "nodes": {
          "127.0.0.1:1995": 1
        },
        "type": "roundrobin"
      }
    }
  ]
}
--- stream_response
hello world



=== TEST 2: rule with bad plugin
--- apisix_json
{
  "stream_routes": [
    {
      "server_addr": "127.0.0.1",
      "server_port": 1985,
      "id": 1,
      "plugins": {
        "mqtt-proxy": {
          "uri": 1
        }
      },
      "upstream": {
        "nodes": {
          "127.0.0.1:1995": 1
        },
        "type": "roundrobin"
      }
    }
  ]
}
--- error_log eval
qr/property "\w+" is required/



=== TEST 3: ignore unknown plugin
--- apisix_json
{
  "stream_routes": [
    {
      "server_addr": "127.0.0.1",
      "server_port": 1985,
      "id": 1,
      "plugins": {
        "x-rewrite": {
          "uri": 1
        }
      },
      "upstream": {
        "nodes": {
          "127.0.0.1:1995": 1
        },
        "type": "roundrobin"
      }
    }
  ]
}
--- stream_response
hello world



=== TEST 4: sanity with plugin
--- apisix_json
{
  "stream_routes": [
    {
      "server_addr": "127.0.0.1",
      "server_port": 1985,
      "id": 1,
      "upstream_id": 1,
      "plugins": {
        "mqtt-proxy": {
          "protocol_name": "MQTT",
          "protocol_level": 4
        }
      }
    }
  ],
  "upstreams": [
    {
      "nodes": {
        "127.0.0.1:1995": 1
      },
      "type": "roundrobin",
      "id": 1
    }
  ]
}
--- stream_request eval
"\x10\x0f\x00\x04\x4d\x51\x54\x54\x04\x02\x00\x3c\x00\x03\x66\x6f\x6f"
--- stream_response
hello world
