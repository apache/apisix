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

# test a domain name is configured as upstream
echo "127.0.0.1 test.com" | sudo tee -a /etc/hosts
echo "::1 ipv6.local" | sudo tee -a /etc/hosts
# test certificate verification
echo "127.0.0.1 admin.apisix.dev" | sudo tee -a /etc/hosts
cat /etc/hosts # check GitHub Action's configuration

# override DNS configures
if [ -f "/etc/netplan/50-cloud-init.yaml" ]; then
    sudo pip3 install yq

    tmp=$(mktemp)
    yq -y '.network.ethernets.eth0."dhcp4-overrides"."use-dns"=false' /etc/netplan/50-cloud-init.yaml | \
    yq -y '.network.ethernets.eth0."dhcp4-overrides"."use-domains"=false' | \
    yq -y '.network.ethernets.eth0.nameservers.addresses[0]="8.8.8.8"' | \
    yq -y '.network.ethernets.eth0.nameservers.search[0]="apache.org"' > $tmp
    mv $tmp /etc/netplan/50-cloud-init.yaml
    cat /etc/netplan/50-cloud-init.yaml
    sudo netplan apply
    sleep 3

    sudo mv /etc/resolv.conf /etc/resolv.conf.bak
    sudo ln -s /run/systemd/resolve/resolv.conf /etc/
fi
cat /etc/resolv.conf

mkdir -p build-cache

if [ ! -f "build-cache/coredns_1_8_1" ]; then
    wget https://github.com/coredns/coredns/releases/download/v1.8.1/coredns_1.8.1_linux_amd64.tgz
    tar -xvf coredns_1.8.1_linux_amd64.tgz
    mv coredns build-cache/

    touch build-cache/coredns_1_8_1
fi

pushd t/coredns || exit 1
../../build-cache/coredns -dns.port=1053 &
popd || exit 1
