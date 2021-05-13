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

. ./ci/common.sh

install_dependencies() {
    export_or_prefix

    # install development tools
    sudo apt install -y cpanminus build-essential libncurses5-dev libreadline-dev libssl-dev perl libpcre3-dev zip

    # install openresty
    wget -O - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
    echo "deb http://openresty.org/package/arm64/ubuntu $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/openresty.list
    sudo apt-get update
    sudo apt-get -y install openresty openresty-openssl111-dev

    # install luarocks
    ./utils/linux-install-luarocks.sh

    # install etcd
    wget https://github.com/etcd-io/etcd/releases/download/v3.4.13/etcd-v3.4.13-linux-arm64.tar.gz
    tar -xvf etcd-v3.4.13-linux-arm64.tar.gz && \
        cd etcd-v3.4.13-linux-arm64 && \
        sudo cp -a etcd etcdctl /usr/bin/

    # install test::nginx
    sudo cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)

    # install and start grpc_server_example
    ## install golang to build grpc_server_example for arm for now
    wget https://golang.org/dl/go1.16.4.linux-arm64.tar.gz
    tar -C /usr/local -xzf go1.16.4.linux-arm64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    go version

    mkdir build-cache

    mv grpc_server_example build-cache/
    git clone https://github.com/iresty/grpc_server_example.git grpc_server_example
    cd grpc_server_example
    go build
    mv grpc_server_example ../build-cache/ && mv proto/ ../build-cache/
    cd ..
    ./build-cache/grpc_server_example \
        -grpc-address :50051 -grpcs-address :50052 -grpcs-mtls-address :50053 \
        -crt ./t/certs/apisix.crt -key ./t/certs/apisix.key -ca ./t/certs/mtls_ca.crt \
        > grpc_server_example.log 2>&1 || (cat grpc_server_example.log && exit 1)&

    # wait for grpc_server_example to fully start
    sleep 3

    # install dependencies
    git clone https://github.com/iresty/test-nginx.git test-nginx
    make deps
}

run_case() {
    export_or_prefix
    make init
    ./utils/set-dns.sh
    # run test cases
    FLUSH_ETCD=1 prove -I./test-nginx/lib -I./ -r t/
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
