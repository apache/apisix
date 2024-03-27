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

export_version_info() {
    source ./.requirements
}

export_or_prefix() {
    export OPENRESTY_PREFIX="/usr/local/openresty"

    export PATH=$OPENRESTY_PREFIX/nginx/sbin:$OPENRESTY_PREFIX/luajit/bin:$OPENRESTY_PREFIX/bin:$PATH
    export OPENSSL_PREFIX=$OPENRESTY_PREFIX/openssl3
    export OPENSSL_BIN=$OPENSSL_PREFIX/bin/openssl
}

create_lua_deps() {
    echo "Create lua deps"

    make deps
    # maybe reopen this feature later
    # luarocks install luacov-coveralls --tree=deps --local > build.log 2>&1 || (cat build.log && exit 1)
    # for github action cache
    chmod -R a+r deps
}

rerun_flaky_tests() {
    if tail -1 "$1" | grep "Result: PASS"; then
        exit 0
    fi

    if ! tail -1 "$1" | grep "Result: FAIL"; then
        # CI failure not caused by failed test
        exit 1
    fi

    local tests
    local n_test
    tests="$(awk '/^t\/.*.t\s+\(.+ Failed: .+\)/{ print $1 }' "$1")"
    n_test="$(echo "$tests" | wc -l)"
    if [ "$n_test" -gt 10 ]; then
        # too many tests failed
        exit 1
    fi

    echo "Rerun $(echo "$tests" | xargs)"
    FLUSH_ETCD=1 prove --timer -I./test-nginx/lib -I./ $(echo "$tests" | xargs)
}

install_curl () {
    CURL_VERSION="7.88.0"
    wget -q https://curl.se/download/curl-${CURL_VERSION}.tar.gz
    tar -xzf curl-${CURL_VERSION}.tar.gz
    cd curl-${CURL_VERSION}
    ./configure --prefix=/usr/local --with-openssl --with-nghttp2
    make
    sudo make install
    sudo ldconfig
    cd ..
    rm -rf curl-${CURL_VERSION}
    curl -V
}

install_apisix_runtime() {
    export runtime_version=${APISIX_RUNTIME}
    wget "https://raw.githubusercontent.com/api7/apisix-build-tools/apisix-runtime/${APISIX_RUNTIME}/build-apisix-runtime.sh"
    chmod +x build-apisix-runtime.sh
    ./build-apisix-runtime.sh latest
}

install_grpcurl () {
    # For more versions, visit https://github.com/fullstorydev/grpcurl/releases
    GRPCURL_VERSION="1.8.5"
    wget -q https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VERSION}/grpcurl_${GRPCURL_VERSION}_linux_x86_64.tar.gz
    tar -xvf grpcurl_${GRPCURL_VERSION}_linux_x86_64.tar.gz -C /usr/local/bin
}

install_vault_cli () {
    VAULT_VERSION="1.9.0"
    # the certificate can't be verified in CentOS7, see
    # https://blog.devgenius.io/lets-encrypt-change-affects-openssl-1-0-x-and-centos-7-49bd66016af3
    wget -q --no-check-certificate https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip
    unzip vault_${VAULT_VERSION}_linux_amd64.zip && mv ./vault /usr/local/bin
}

install_nodejs () {
    NODEJS_PREFIX="/usr/local/node"
    NODEJS_VERSION="16.13.1"
    wget -q https://nodejs.org/dist/v${NODEJS_VERSION}/node-v${NODEJS_VERSION}-linux-x64.tar.xz
    tar -xf node-v${NODEJS_VERSION}-linux-x64.tar.xz
    rm -f /usr/local/bin/node
    rm -f /usr/local/bin/npm
    mv node-v${NODEJS_VERSION}-linux-x64 ${NODEJS_PREFIX}
    ln -s ${NODEJS_PREFIX}/bin/node /usr/local/bin/node
    ln -s ${NODEJS_PREFIX}/bin/npm /usr/local/bin/npm

    npm config set registry https://registry.npmjs.org/
}

install_brotli () {
    local BORTLI_VERSION="1.1.0"
    wget -q https://github.com/google/brotli/archive/refs/tags/v${BORTLI_VERSION}.zip
    unzip v${BORTLI_VERSION}.zip && cd ./brotli-${BORTLI_VERSION} && mkdir build && cd build
    local CMAKE=$(command -v cmake3 > /dev/null 2>&1 && echo cmake3 || echo cmake)
    ${CMAKE} -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local/brotli ..
    sudo ${CMAKE} --build . --config Release --target install
    if [ -d "/usr/local/brotli/lib64" ]; then
        echo /usr/local/brotli/lib64 | sudo tee /etc/ld.so.conf.d/brotli.conf
    else
        echo /usr/local/brotli/lib | sudo tee /etc/ld.so.conf.d/brotli.conf
    fi
    sudo ldconfig
    cd ../..
    rm -rf brotli-${BORTLI_VERSION}
}

set_coredns() {
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
        wget -q https://github.com/coredns/coredns/releases/download/v1.8.1/coredns_1.8.1_linux_amd64.tgz
        tar -xvf coredns_1.8.1_linux_amd64.tgz
        mv coredns build-cache/

        touch build-cache/coredns_1_8_1
    fi

    pushd t/coredns || exit 1
    ../../build-cache/coredns -dns.port=1053 &
    popd || exit 1

    touch build-cache/test_resolve.conf
    echo "nameserver 127.0.0.1:1053" > build-cache/test_resolve.conf
}

GRPC_SERVER_EXAMPLE_VER=20210819

linux_get_dependencies () {
    apt update
    apt install -y cpanminus build-essential libncurses5-dev libreadline-dev libssl-dev perl libpcre3 libpcre3-dev libldap2-dev libyaml-devel
}

function start_grpc_server_example() {
    ./t/grpc_server_example/grpc_server_example \
        -grpc-address :10051 -grpcs-address :10052 -grpcs-mtls-address :10053 -grpc-http-address :10054 \
        -crt ./t/certs/apisix.crt -key ./t/certs/apisix.key -ca ./t/certs/mtls_ca.crt \
        > grpc_server_example.log 2>&1 &

    for (( i = 0; i <= 10; i++ )); do
        sleep 0.5
        GRPC_PROC=`ps -ef | grep grpc_server_example | grep -v grep || echo "none"`
        if [[ $GRPC_PROC == "none" || "$i" -eq 10 ]]; then
            echo "failed to start grpc_server_example"
            ss -antp | grep 1005 || echo "no proc listen port 1005x"
            cat grpc_server_example.log

            exit 1
        fi

        ss -lntp | grep 10051 | grep grpc_server && break
    done
}
