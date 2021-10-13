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

docker run -d --rm --name etcd_mtls \
    -p 22379:22379 -p 22380:22380 \
    -e ALLOW_NONE_AUTHENTICATION=yes \
    -e ETCD_ADVERTISE_CLIENT_URLS=https://0.0.0.0:22379 \
    -e ETCD_LISTEN_CLIENT_URLS=https://0.0.0.0:22379 \
    -e ETCD_CERT_FILE=/certs/mtls_server.crt \
    -e ETCD_KEY_FILE=/certs/mtls_server.key \
    -e ETCD_CLIENT_CERT_AUTH=true \
    -e ETCD_TRUSTED_CA_FILE=/certs/mtls_ca.crt \
    -v "$PWD"/t/certs:/certs \
    bitnami/etcd:3.4.0
