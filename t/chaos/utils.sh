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

startMinikube() {
    curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin/kubectl

    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube_latest_amd64.deb
    sudo dpkg -i minikube_latest_amd64.deb
    sudo mv ./minikube /usr/local/bin/minikube
    minikube start
}

ensure_pods_ready() {
    local app=$1
    local status=$2

    count=0
    while [ -n "$(kubectl get pods -l app=${app} -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != ${status})" ];
    do
        echo "Waiting for pod running" && sleep 10;

        ((count=count+1))
        # waiting for 300s, or timeout
        if [ $count -gt 30 ]; then
            printf "Waiting for pod status running timeout\n"
            exit 1
        fi
    done
}

"$@"
