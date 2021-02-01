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

. ./apisix/.travis/common.sh

install_dependencies() {
    export_or_prefix

    # install development tools
    yum install -y wget tar gcc automake autoconf libtool make unzip \
        curl git which sudo

    # install epel and luarocks
    wget http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    rpm -ivh epel-release-latest-7.noarch.rpm
    yum install -y lua-devel

    ./apisix/utils/linux-install-luarocks.sh

    # install openresty
    yum install -y yum-utils && yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo
    yum install -y openresty-debug
    yum install -y openresty-openssl-debug-devel

    # install etcdctl
    wget https://github.com/etcd-io/etcd/releases/download/v3.4.0/etcd-v3.4.0-linux-amd64.tar.gz
    tar xf etcd-v3.4.0-linux-amd64.tar.gz
    cp /etcd-v3.4.0-linux-amd64/etcdctl /usr/local/bin/
    rm -rf etcd-v3.4.0-linux-amd64

    # install test::nginx
    yum install -y cpanminus build-essential libncurses5-dev libreadline-dev libssl-dev perl
    cp -r /tmp/apisix ./apisix
    cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)

    # install and start grpc_server_example
    mkdir build-cache
    wget https://github.com/iresty/grpc_server_example/releases/download/20200901/grpc_server_example-amd64.tar.gz
    tar -xvf grpc_server_example-amd64.tar.gz
    mv grpc_server_example build-cache/
    git clone https://github.com/iresty/grpc_server_example.git grpc_server_example
    cd grpc_server_example/ && mv proto/ ../build-cache/ && cd ..
    ./build-cache/grpc_server_example > grpc_server_example.log 2>&1 || (cat grpc_server_example.log && exit 1)&

    # wait for grpc_server_example to fully start
    sleep 3

    # install dependencies
    cd apisix
    make deps
    make init
    git clone https://github.com/iresty/test-nginx.git test-nginx
}

run_case() {
    export_or_prefix

    cd apisix

    # run test cases
    prove -Itest-nginx/lib -I./ -r t/
}

case_opt=$1
case $case_opt in
    (install_dependencies)
        install_dependencies
        ;;
    (run_case)
        run_case
        ;;
esac
