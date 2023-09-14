#!/usr/bin/env bash

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

. ./t/cli/common.sh

echo '
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml

apisix:
  router:
    http: radixtree_uri

nginx_config:
  worker_processes: 1

' > conf/config.yaml

echo '
routes:
  - uri: "/hello"
    hosts:
      - test.com
    vars:
      - - "graphql_name"
        - "=="
        - "createAccount"
    priority: 30
    id: "graphql1"
    upstream_id: "invalid"

  - uri: "/hello"
    hosts:
      - test.com
    plugins:
      echo:
        body: "test server"
    priority: 20
    id: "graphql2"
    upstream_id: "invalid"

  - uri: "/hello"
    hosts:
      - test2.com
    plugins:
      echo:
        body: "test2"
    priority: 20
    id: "graphql3"
    upstream_id: "invalid"

upstreams:
  - nodes:
      127.0.0.1:1999: 1
    id: "invalid"
#END
' > conf/apisix.yaml

make run

dd if=/dev/urandom of=tmp_data.json bs=300K count=1

for i in {1..100}; do
    curl -s http://127.0.0.1:9080/hello -H "Host: test.com" -H "Content-Type: application/json" -X POST -d @tmp_data.json > /tmp/graphql_request1.txt &
    curl -s http://127.0.0.1:9080/hello -H "Host: test2.com" -H "Content-Type: application/json" -X POST -d @tmp_data.json > /tmp/graphql_request2.txt &

    wait

    if diff /tmp/graphql_request1.txt /tmp/graphql_request2.txt > /dev/null; then
        make stop
        echo "failed: route match error in GraphQL requests, route should not be the same"
        exit 1
    fi
done

make stop

rm tmp_data.json /tmp/graphql_request1.txt /tmp/graphql_request2.txt

echo "passed: GraphQL requests can be correctly matched to the route"
