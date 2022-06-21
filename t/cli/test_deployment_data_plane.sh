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

# clean etcd data
etcdctl del / --prefix

# data_plane does not write data to etcd
echo '
deployment:
    role: data_plane
    role_data_plane:
        config_provider: control_plane
        control_plane:
            host:
                - http://127.0.0.1:2379
            timeout: 30
    certs:
        cert: /path/to/ca-cert
        cert_key: /path/to/ca-cert
        trusted_ca_cert: /path/to/ca-cert
' > conf/config.yaml

make run

sleep 1

res=$(etcdctl get / --prefix | wc -l)

if [ ! $res -eq 0 ]; then
    echo "failed: data_plane should not write data to etcd"
    exit 1
fi

echo "passed: data_plane does not write data to etcd"
