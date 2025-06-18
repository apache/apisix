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

=== TEST 1: validate consumer
--- apisix_json
{
  "routes": [
    {
      "uri": "/hello",
      "upstream": {
        "nodes": {
          "127.0.0.1:1980": 1
        },
        "type": "roundrobin"
      }
    }
  ],
  "consumers": [
    {
      "username": "jwt#auth"
    }
  ]
}
--- request
GET /hello
--- response_body
hello world
--- error_log
property "username" validation failed



=== TEST 2: consumer restriction
--- apisix_json
{
  "consumers": [
    {
      "username": "jack",
      "plugins": {
        "key-auth": {
          "key": "user-key"
        }
      }
    }
  ],
  "routes": [
    {
      "id": "1",
      "methods": ["POST"],
      "uri": "/hello",
      "plugins": {
        "key-auth": {},
        "consumer-restriction": {
          "whitelist": ["jack"]
        }
      },
      "upstream": {
        "type": "roundrobin",
        "nodes": {
          "127.0.0.1:1980": 1
        }
      }
    }
  ]
}
--- more_headers
apikey: user-key
--- request
POST /hello
