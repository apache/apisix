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
    export_version_info
    export_or_prefix

    # install build & runtime deps
    yum install -y wget tar gcc gcc-c++ automake autoconf libtool make unzip patch \
        git sudo openldap-devel which ca-certificates\
        epel-release  \
        cpanminus perl \
        openssl-devel

    yum install -y --enablerepo=ol7_codeready_builder libyaml-devel
    # install newer curl
    yum makecache
    yum install -y libnghttp2-devel
    install_curl

    yum -y install centos-release-scl
    yum -y install devtoolset-9 patch wget git make sudo
    set +eu
    source scl_source enable devtoolset-9
    set -eu

    # install openresty to make apisix's rpm test work
    yum install -y yum-utils && yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo
    yum install -y openresty-pcre-devel openresty-zlib-devel

    install_apisix_runtime
    curl -o /usr/local/openresty/openssl3/ssl/openssl.cnf \
        https://raw.githubusercontent.com/api7/apisix-build-tools/apisix-runtime/${APISIX_RUNTIME}/conf/openssl3/openssl.cnf

    # patch lua-resty-events
    sed -i 's/log(ERR, "event worker failed: ", perr)/log(ngx.WARN, "event worker failed: ", perr)/' /usr/local/openresty/lualib/resty/events/worker.lua

    # install luarocks
    ./utils/linux-install-luarocks.sh

    # install etcdctl
    ./ci/linux-install-etcd-client.sh

    # install vault cli capabilities
    install_vault_cli

    # install brotli
    yum install -y cmake3
    install_brotli

    # install test::nginx
    yum install -y cpanminus perl
    cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)

    # add go1.15 binary to the path
    mkdir build-cache
    # centos-7 ci runs on a docker container with the centos image on top of ubuntu host. Go is required inside the container.
    cd build-cache/ && wget -q https://golang.org/dl/go1.17.linux-amd64.tar.gz && tar -xf go1.17.linux-amd64.tar.gz
    export PATH=$PATH:$(pwd)/go/bin
    cd ..
    # install and start grpc_server_example
    cd t/grpc_server_example

    CGO_ENABLED=0 go build
    cd ../../

    start_grpc_server_example

    # installing grpcurl
    install_grpcurl

    # install nodejs
    install_nodejs

    # grpc-web server && client
    cd t/plugin/grpc-web
    ./setup.sh
    # back to home directory
    cd ../../../

    # install dependencies
    git clone https://github.com/openresty/test-nginx.git test-nginx
    create_lua_deps
}

run_case() {
    export_or_prefix
    make init
    set_coredns
    # run test cases
    FLUSH_ETCD=1 TEST_EVENTS_MODULE=$TEST_EVENTS_MODULE prove --timer -Itest-nginx/lib -I./ -r ${TEST_FILE_SUB_DIR} | tee /tmp/test.result
    rerun_flaky_tests /tmp/test.result
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
