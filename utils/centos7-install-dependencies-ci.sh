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

#!/bin/bash

set -ex

docker exec centos7Instance bash -c "yum install -y wget tar gcc automake autoconf libtool make && wget http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm && rpm -ivh epel-release-latest-7.noarch.rpm"
docker exec centos7Instance bash -c "yum install -y curl git luarocks lua-devel which"
docker exec centos7Instance bash -c "yum install -y yum-utils && yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo"
docker exec centos7Instance bash -c "yum install -y openresty-debug"
docker exec centos7Instance bash -c "wget https://github.com/etcd-io/etcd/releases/download/v3.4.0/etcd-v3.4.0-linux-amd64.tar.gz && tar xf etcd-v3.4.0-linux-amd64.tar.gz"
docker exec centos7Instance bash -c "cp /etcd-v3.4.0-linux-amd64/etcdctl /usr/local/bin/ && rm -rf etcd-v3.4.0-linux-amd64"
docker exec centos7Instance bash -c "yum install -y cpanminus build-essential libncurses5-dev libreadline-dev libssl-dev perl"
docker exec centos7Instance bash -c "cp -r /tmp/apisix ./"
docker exec centos7Instance bash -c "PATH=/usr/local/openresty-debug/nginx/sbin:/usr/local/openresty-debug/bin:$PATH cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)"
docker exec centos7Instance bash -c "mkdir build-cache && wget https://github.com/iresty/grpc_server_example/releases/download/20200901/grpc_server_example-amd64.tar.gz && tar -xvf grpc_server_example-amd64.tar.gz && mv grpc_server_example build-cache/"
docker exec centos7Instance bash -c "git clone https://github.com/iresty/grpc_server_example.git grpc_server_example && cd grpc_server_example/ && mv proto/ ../build-cache/"
docker exec centos7Instance bash -c "./build-cache/grpc_server_example > grpc_server_example.log 2>&1 || (cat grpc_server_example.log && exit 1)&"
sleep 3
docker exec centos7Instance bash -c "cd apisix && PATH=/usr/local/openresty-debug/nginx/sbin:/usr/local/openresty-debug/bin:$PATH make deps"
docker exec centos7Instance bash -c "cd apisix && PATH=/usr/local/openresty-debug/nginx/sbin:/usr/local/openresty-debug/bin:$PATH make init"
docker exec centos7Instance bash -c "cd apisix && git clone https://github.com/iresty/test-nginx.git test-nginx"
