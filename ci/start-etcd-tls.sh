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
if [ $# -gt 0 ]; then
    APISIX_DIR="$1"
else
    APISIX_DIR="$PWD"
fi

docker run -d --rm --name etcd_tls \
    -p 12379:12379 -p 12380:12380 \
    -e ALLOW_NONE_AUTHENTICATION=yes \
    -e ETCD_ADVERTISE_CLIENT_URLS=https://0.0.0.0:12379 \
    -e ETCD_LISTEN_CLIENT_URLS=https://0.0.0.0:12379 \
    -e ETCD_CERT_FILE=/certs/etcd.pem \
    -e ETCD_KEY_FILE=/certs/etcd.key \
    -v "$APISIX_DIR"/t/certs:/certs \
    bitnami/etcd:3.4.0
