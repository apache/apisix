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
    yum install -y --disablerepo=* --enablerepo=ubi-8-appstream-rpms --enablerepo=ubi-8-baseos-rpms \
    wget tar gcc automake autoconf libtool make unzip git sudo openldap-devel hostname \
    which ca-certificates openssl-devel

    # install newer curl
    yum makecache
    yum install -y libnghttp2-devel
    install_curl

    # install apisix-runtime to make apisix's rpm test work
    yum install -y yum-utils && yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo
    rpm --import https://repos.apiseven.com/KEYS
    yum install -y openresty-openssl111 openresty-openssl111-devel pcre pcre pcre-devel xz
    yum -y install https://repos.apiseven.com/packages/centos/apache-apisix-repo-1.0-1.noarch.rpm

    wget "https://raw.githubusercontent.com/api7/apisix-build-tools/apisix-runtime/${APISIX_RUNTIME}/build-apisix-runtime-debug-centos7.sh"
    wget "https://raw.githubusercontent.com/api7/apisix-build-tools/apisix-runtime/${APISIX_RUNTIME}/build-apisix-runtime.sh"
    chmod +x build-apisix-runtime.sh
    chmod +x build-apisix-runtime-debug-centos7.sh
    ./build-apisix-runtime-debug-centos7.sh

    # install luarocks
    ./utils/linux-install-luarocks.sh

    # install etcdctl
    ./ci/linux-install-etcd-client.sh

    # install vault cli capabilities
    install_vault_cli

    # install test::nginx
    yum install -y --disablerepo=* --enablerepo=ubi-8-appstream-rpms --enablerepo=ubi-8-baseos-rpms cpanminus perl
    cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)

    # add go1.15 binary to the path
    mkdir build-cache
    pushd build-cache/
    # Go is required inside the container.
    wget -q https://golang.org/dl/go1.17.linux-amd64.tar.gz && tar -xf go1.17.linux-amd64.tar.gz
    export PATH=$PATH:$(pwd)/go/bin
    popd
    # install and start grpc_server_example
    pushd t/grpc_server_example

    CGO_ENABLED=0 go build
    popd

    yum install -y iproute procps
    start_grpc_server_example

    # installing grpcurl
    install_grpcurl

    # install nodejs
    install_nodejs

    # grpc-web server && client
    pushd t/plugin/grpc-web
    ./setup.sh
    # back to home directory
    popd

    # install dependencies
    git clone https://github.com/openresty/test-nginx.git test-nginx
    create_lua_deps
}

run_case() {
    export_or_prefix
    make init
    set_coredns
    # run test cases
    FLUSH_ETCD=1 prove --timer -Itest-nginx/lib -I./ -r ${TEST_FILE_SUB_DIR} | tee /tmp/test.result
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
