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

before_install() {
    linux_get_dependencies

    sudo cpanm --notest Test::Nginx >build.log 2>&1 || (cat build.log && exit 1)
}

do_install() {
    export_or_prefix

    ./utils/linux-install-openresty.sh

    ./utils/linux-install-luarocks.sh

    ./utils/linux-install-etcd-client.sh

    create_lua_deps

    # sudo apt-get install tree -y
    # tree deps

    git clone --depth 1 https://github.com/openresty/test-nginx.git test-nginx
    make utils

    mkdir -p build-cache
    # install and start grpc_server_example
    cd t/grpc_server_example

    CGO_ENABLED=0 go build
    cd ../../

    # install grpcurl
    install_grpcurl

    # install nodejs
    install_nodejs

    # grpc-web server && client
    cd t/plugin/grpc-web
    ./setup.sh
    # back to home directory
    cd ../../../

    # install vault cli capabilities
    install_vault_cli
}

script() {
    export_or_prefix
    openresty -V

    set_coredns

    ./t/grpc_server_example/grpc_server_example \
        -grpc-address :50051 -grpcs-address :50052 -grpcs-mtls-address :50053 -grpc-http-address :50054 \
        -crt ./t/certs/apisix.crt -key ./t/certs/apisix.key -ca ./t/certs/mtls_ca.crt \
        &

    # ensure grpc server example is already started
    for (( i = 0; i <= 100; i++ )); do
        if [[ "$i" -eq 100 ]]; then
            echo "failed to start grpc_server_example in time"
            exit 1
        fi
        nc -zv 127.0.0.1 50051 && break
        sleep 1
    done

    # APISIX_ENABLE_LUACOV=1 PERL5LIB=.:$PERL5LIB prove -Itest-nginx/lib -r t
    FLUSH_ETCD=1 prove --timer -Itest-nginx/lib -I./ -r $TEST_FILE_SUB_DIR | tee /tmp/test.result
    rerun_flaky_tests /tmp/test.result
}

after_success() {
    # cat luacov.stats.out
    # luacov-coveralls
    echo "done"
}

case_opt=$1
shift

case ${case_opt} in
before_install)
    before_install "$@"
    ;;
do_install)
    do_install "$@"
    ;;
script)
    script "$@"
    ;;
after_success)
    after_success "$@"
    ;;
esac
