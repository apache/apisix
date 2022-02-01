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

cleanup() {
   rm -rf deps
   rm -rf test-nginx
}

install_dependencies() {
    export_or_prefix

    # install development tools
    yum install -y wget tar gcc automake autoconf libtool make unzip \
        git which sudo openldap-devel

    # curl with http2
    wget https://github.com/moparisthebest/static-curl/releases/download/v7.79.1/curl-amd64 -O /usr/bin/curl
    # install openresty to make apisix's rpm test work
    yum install -y yum-utils && yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo
    yum install -y openresty openresty-debug openresty-openssl111-debug-devel pcre pcre-devel

    # install luarocks
    ./utils/linux-install-luarocks.sh

    # install test::nginx
    yum install -y cpanminus perl
    cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)

    # unless pulled recursively, the submodule directory will remain empty. So it's better to initialize and set the submodule to the particular commit.
    if [ ! "$(ls -A . )" ]; then
        git submodule init
        git submodule update
    fi

    # install dependencies
    git clone https://github.com/iresty/test-nginx.git test-nginx
    create_lua_deps
}

run_case() {
    export_or_prefix
    export PERL5LIB=.:$PERL5LIB
    prove -Itest-nginx/lib -r t/discovery/kubernetes/kubernetes.t | tee /tmp/test.result
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
    (cleanup)
        cleanup
        ;;
esac
