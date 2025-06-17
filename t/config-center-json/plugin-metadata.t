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


run_tests();

__DATA__

=== TEST 1: sanity
--- apisix_json
{
  "upstreams": [
    {
      "id": 1,
      "nodes": {
        "127.0.0.1:1980": 1
      },
      "type": "roundrobin"
    }
  ],
  "routes": [
    {
      "uri": "/hello",
      "upstream_id": 1,
      "plugins": {
        "http-logger": {
          "batch_max_size": 1,
          "uri": "http://127.0.0.1:1980/log"
        }
      }
    }
  ],
  "plugin_metadata": [
    {
      "id": "http-logger",
      "log_format": {
        "host": "$host",
        "remote_addr": "$remote_addr"
      }
    }
  ]
}
--- request
GET /hello
--- error_log
"remote_addr":"127.0.0.1"
--- no_error_log
failed to get schema for plugin:
=== TEST 2: sanity
--- apisix_json
{
  "upstreams": [
    {
      "id": 1,
      "nodes": {
        "127.0.0.1:1980": 1
      },
      "type": "roundrobin"
    }
  ],
  "routes": [
    {
      "uri": "/hello",
      "upstream_id": 1
    }
  ],
  "plugin_metadata": [
    {
      "id": "authz-casbin",
      "model": 123
    }
  ]
}
--- request
GET /hello
--- error_log
failed to check item data of [plugin_metadata]
