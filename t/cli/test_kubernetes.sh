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
discovery:
    kubernetes:
      service:
        host: ${HOST_ENV}
      client:
        token: ${TOKEN_ENV}
' >conf/config.yaml

make init

if ! grep "env HOST_ENV" conf/nginx.conf; then
  echo "kubernetes discovery env inject failed"
  exit 1
fi

if ! grep "env KUBERNETES_SERVICE_PORT" conf/nginx.conf; then
  echo "kubernetes discovery env inject failed"
  exit 1
fi

if ! grep "env TOKEN_ENV" conf/nginx.conf; then
  echo "kubernetes discovery env inject failed"
  exit 1
fi

if ! grep "lua_shared_dict kubernetes 1m;" conf/nginx.conf; then
  echo "kubernetes discovery lua_shared_dict inject failed"
  exit 1
fi

echo '
discovery:
    kubernetes:
      - id: dev
        service:
          host: ${DEV_HOST}
          port: ${DEV_PORT}
        client:
          token: ${DEV_TOKEN}
      - id: pro
        service:
          host: ${PRO_HOST}
          port: ${PRO_PORT}
        client:
          token: ${PRO_TOKEN}
        shared_size: 2m
' >conf/config.yaml

make init

if ! grep "env DEV_HOST" conf/nginx.conf; then
  echo "kubernetes discovery env inject failed"
  exit 1
fi

if ! grep "env DEV_PORT" conf/nginx.conf; then
  echo "kubernetes discovery env inject failed"
  exit 1
fi

if ! grep "env DEV_TOKEN" conf/nginx.conf; then
  echo "kubernetes discovery env inject failed"
  exit 1
fi

if ! grep "env PRO_HOST" conf/nginx.conf; then
  echo "kubernetes discovery env inject failed"
  exit 1
fi

if ! grep "env PRO_PORT" conf/nginx.conf; then
  echo "kubernetes discovery env inject failed"
  exit 1
fi

if ! grep "env PRO_TOKEN" conf/nginx.conf; then
  echo "kubernetes discovery env inject failed"
  exit 1
fi

if ! grep "lua_shared_dict kubernetes-dev 1m;" conf/nginx.conf; then
  echo "kubernetes discovery lua_shared_dict inject failed"
  exit 1
fi

if ! grep "lua_shared_dict kubernetes-pro 2m;" conf/nginx.conf; then
  echo "kubernetes discovery lua_shared_dict inject failed"
  exit 1
fi

echo "kubernetes discovery inject success"
