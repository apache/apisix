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

# check etcd while enable auth
git checkout conf/config.yaml

# Make new routes
etcdctl --endpoints=127.0.0.1:2379 del --prefix /apisix/routes/
etcdctl --endpoints=127.0.0.1:2379 put /apisix/routes/ init_dir
etcdctl --endpoints=127.0.0.1:2379 put /apisix/routes/1 '{"uri":"/1","plugins":{}}'
etcdctl --endpoints=127.0.0.1:2379 put /apisix/routes/2 '{"uri":"/2","plugins":{}}'
etcdctl --endpoints=127.0.0.1:2379 put /apisix/routes/3 '{"uri":"/3","plugins":{}}'
etcdctl --endpoints=127.0.0.1:2379 put /apisix/routes/4 '{"uri":"/4","plugins":{}}'
etcdctl --endpoints=127.0.0.1:2379 put /apisix/routes/5 '{"uri":"/5","plugins":{}}'

# Connect by unauthenticated
echo '
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - http://127.0.0.1:2379
    prefix: /apisix
nginx_config:
  error_log_level: info
  worker_processes: 1
' > conf/config.yaml

# Initialize and start APISIX without password
make init
make run

# Test request
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/1 | grep 503 || (echo "failed: Round 1 Request 1 unexpected"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/2 | grep 503 || (echo "failed: Round 1 Request 2 unexpected"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/3 | grep 503 || (echo "failed: Round 1 Request 3 unexpected"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/4 | grep 503 || (echo "failed: Round 1 Request 4 unexpected"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/5 | grep 503 || (echo "failed: Round 1 Request 5 unexpected"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/6 | grep 404 || (echo "failed: Round 1 Request 6 unexpected"; exit 1)

# Enable auth to block APISIX connect
export ETCDCTL_API=3
etcdctl version
etcdctl --endpoints=127.0.0.1:2379 user add "root:apache-api6-sync"
etcdctl --endpoints=127.0.0.1:2379 role add root
etcdctl --endpoints=127.0.0.1:2379 user grant-role root root
etcdctl --endpoints=127.0.0.1:2379 user get root
etcdctl --endpoints=127.0.0.1:2379 auth enable
sleep 3

# Restart etcd services to make sure that APISIX cannot be synchronized
project_compose_ci=ci/pod/docker-compose.common.yml make ci-env-stop
project_compose_ci=ci/pod/docker-compose.common.yml make ci-env-up

# Make some changes when APISIX cannot be synchronized
# Authentication ensures that only etcdctl can access etcd at this time
etcdctl --endpoints=127.0.0.1:2379 --user=root:apache-api6-sync put /apisix/routes/1 '{"uri":"/1","plugins":{"fault-injection":{"abort":{"http_status":204}}}}'
etcdctl --endpoints=127.0.0.1:2379 --user=root:apache-api6-sync put /apisix/routes/2 '{"uri":"/2"}' ## set incorrect configuration
etcdctl --endpoints=127.0.0.1:2379 --user=root:apache-api6-sync put /apisix/routes/3 '{"uri":"/3","plugins":{"fault-injection":{"abort":{"http_status":204}}}}'
etcdctl --endpoints=127.0.0.1:2379 --user=root:apache-api6-sync put /apisix/routes/4 '{"uri":"/4","plugins":{"fault-injection":{"abort":{"http_status":204}}}}'
etcdctl --endpoints=127.0.0.1:2379 --user=root:apache-api6-sync put /apisix/routes/5 '{"uri":"/5","plugins":{"fault-injection":{"abort":{"http_status":204}}}}'

# Resume APISIX synchronization by disable auth
# Since APISIX will not be able to access etcd until authentication is disable,
# watch will be temporarily disabled, so when authentication is disable,
# the backlog events will be sent at once at an offset from when APISIX disconnects.
# When APISIX resumes the connection, it still has not met its mandatory full
# synchronization condition, so it will be "watch" that resumes, not "readdir".
etcdctl --endpoints=127.0.0.1:2379 --user=root:apache-api6-sync auth disable
etcdctl --endpoints=127.0.0.1:2379 user delete root
etcdctl --endpoints=127.0.0.1:2379 role delete root
sleep 5 # wait resync by watch

# Test request
# All but the intentionally incoming misconfigurations should be applied,
# and non-existent routes will remain non-existent.
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/1 | grep 204 || (echo "failed: Round 2 Request 1 unexpected"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/2 | grep 503 || (echo "failed: Round 2 Request 2 unexpected"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/3 | grep 204 || (echo "failed: Round 2 Request 3 unexpected"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/4 | grep 204 || (echo "failed: Round 2 Request 4 unexpected"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/5 | grep 204 || (echo "failed: Round 2 Request 5 unexpected"; exit 1)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9080/6 | grep 404 || (echo "failed: Round 2 Request 6 unexpected"; exit 1)

# Check logs
## Case1: Ensure etcd is disconnected
cat logs/error.log | grep "watchdir err: has no healthy etcd endpoint available" || (echo "Log case 1 unexpected"; exit 1)

## Case2: Ensure events are sent in bulk after connection is restored
## It is extracted from the structure of following type
## result = {
##   events = { {
##     {
##       kv = {
##         key = "/apisix/routes/1",
##         ...
##       }
####   }, {
##       kv = {
##         key = "/apisix/routes/2",
##         ...
##       }
##     },
##     ...
##   } },
##   header = {
##     ...
##   }
## }
## After check, it only appears when watch recovers and returns events in bulk.
cat logs/error.log | grep "}, {" || (echo "failed: Log case 2 unexpected"; exit 1)

## Case3: Ensure that the check schema error is actually triggered.
cat logs/error.log | grep "failed to check item data" || (echo "failed: Log case 3 unexpected"; exit 1)
