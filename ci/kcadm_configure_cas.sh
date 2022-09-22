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

set -ex

export PATH=/opt/keycloak/bin:$PATH

kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password admin

kcadm.sh create realms -s realm=test -s enabled=true

kcadm.sh create users -r test -s username=test -s enabled=true
kcadm.sh set-password -r test --username test --new-password test

clients=("cas1" "cas2")
rootUrls=("http://127.0.0.1:1984" "http://127.0.0.2:1984")

for i in ${!clients[@]}; do
    kcadm.sh create clients -r test -s clientId=${clients[$i]} -s enabled=true \
        -s protocol=cas -s frontchannelLogout=false -s rootUrl=${rootUrls[$i]} -s 'redirectUris=["/*"]'
done
