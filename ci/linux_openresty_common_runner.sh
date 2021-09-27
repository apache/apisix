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
    sudo cpanm --notest Test::Nginx >build.log 2>&1 || (cat build.log && exit 1)

    ./ci/install-ext-services-via-docker.sh
}

do_install() {
    export_or_prefix

    ./utils/linux-install-openresty.sh

    ./utils/linux-install-luarocks.sh

    ./utils/linux-install-etcd-client.sh

    create_lua_deps

    # sudo apt-get install tree -y
    # tree deps

    git clone https://github.com/iresty/test-nginx.git test-nginx
    make utils

    mkdir -p build-cache
    if [ ! -f "build-cache/grpc_server_example_$GRPC_SERVER_EXAMPLE_VER" ]; then
        wget https://github.com/api7/grpc_server_example/releases/download/"$GRPC_SERVER_EXAMPLE_VER"/grpc_server_example-amd64.tar.gz
        tar -xvf grpc_server_example-amd64.tar.gz
        mv grpc_server_example build-cache/

        git clone --depth 1 https://github.com/api7/grpc_server_example.git grpc_server_example
        pushd grpc_server_example/ || exit 1
        mv proto/ ../build-cache/
        popd || exit 1

        touch build-cache/grpc_server_example_"$GRPC_SERVER_EXAMPLE_VER"
    fi

    if [ ! -f "build-cache/grpcurl" ]; then
        wget https://github.com/api7/grpcurl/releases/download/20200314/grpcurl-amd64.tar.gz
        tar -xvf grpcurl-amd64.tar.gz
        mv grpcurl build-cache/
    fi
}

script() {
    export_or_prefix
    openresty -V

    ./utils/set-dns.sh

    ./build-cache/grpc_server_example \
        -grpc-address :50051 -grpcs-address :50052 -grpcs-mtls-address :50053 \
        -crt ./t/certs/apisix.crt -key ./t/certs/apisix.key -ca ./t/certs/mtls_ca.crt \
        &

    # listen 9081 for http2 with plaintext
    echo '
apisix:
    node_listen:
        - port: 9080
          enable_http2: false
        - port: 9081
          enable_http2: true
    ' > conf/config.yaml

    ./bin/apisix help
    ./bin/apisix init
    ./bin/apisix init_etcd
    ./bin/apisix start

    #start again  --> fail
    res=`./bin/apisix start`
    if ! echo "$res" | grep "APISIX is running"; then
        echo "failed: APISIX runs repeatedly"
        exit 1
    fi

    #kill apisix
    sudo kill -9 `ps aux | grep apisix | grep nginx | awk '{print $2}'`

    #start -> ok
    res=`./bin/apisix start`
    if echo "$res" | grep "APISIX is running"; then
        echo "failed: shouldn't stop APISIX running after kill the old process."
        exit 1
    fi

    sleep 1
    cat logs/error.log

    ./t/grpc-proxy-test.sh
    sleep 1

    ./bin/apisix stop
    sleep 1

    # APISIX_ENABLE_LUACOV=1 PERL5LIB=.:$PERL5LIB prove -Itest-nginx/lib -r t
    FLUSH_ETCD=1 PERL5LIB=.:$PERL5LIB prove -Itest-nginx/lib -r t
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
