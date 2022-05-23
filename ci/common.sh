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

export_or_prefix() {
    export OPENRESTY_PREFIX="/usr/local/openresty-debug"
    export APISIX_MAIN="https://raw.githubusercontent.com/apache/incubator-apisix/master/rockspec/apisix-master-0.rockspec"
    export PATH=$OPENRESTY_PREFIX/nginx/sbin:$OPENRESTY_PREFIX/luajit/bin:$OPENRESTY_PREFIX/bin:$PATH
}

create_lua_deps() {
    echo "Create lua deps"

    make deps
    # maybe reopen this feature later
    # luarocks install luacov-coveralls --tree=deps --local > build.log 2>&1 || (cat build.log && exit 1)
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
    FLUSH_ETCD=1 prove -I./test-nginx/lib -I./ $(echo "$tests" | xargs)
}

install_grpcurl () {
    # For more versions, visit https://github.com/fullstorydev/grpcurl/releases
    GRPCURL_VERSION="1.8.5"
    wget https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VERSION}/grpcurl_${GRPCURL_VERSION}_linux_x86_64.tar.gz
    tar -xvf grpcurl_${GRPCURL_VERSION}_linux_x86_64.tar.gz -C /usr/local/bin
}

install_vault_cli () {
    VAULT_VERSION="1.9.0"
    wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip
    unzip vault_${VAULT_VERSION}_linux_amd64.zip && mv ./vault /usr/local/bin
}

install_nodejs () {
    NODEJS_PREFIX="/usr/local/node"
    NODEJS_VERSION="16.13.1"
    wget https://nodejs.org/dist/v${NODEJS_VERSION}/node-v${NODEJS_VERSION}-linux-x64.tar.xz
    tar -xvf node-v${NODEJS_VERSION}-linux-x64.tar.xz
    rm -f /usr/local/bin/node
    rm -f /usr/local/bin/npm
    mv node-v${NODEJS_VERSION}-linux-x64 ${NODEJS_PREFIX}
    ln -s ${NODEJS_PREFIX}/bin/node /usr/local/bin/node
    ln -s ${NODEJS_PREFIX}/bin/npm /usr/local/bin/npm
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
        wget https://github.com/coredns/coredns/releases/download/v1.8.1/coredns_1.8.1_linux_amd64.tgz
        tar -xvf coredns_1.8.1_linux_amd64.tgz
        mv coredns build-cache/

        touch build-cache/coredns_1_8_1
    fi

    pushd t/coredns || exit 1
    ../../build-cache/coredns -dns.port=1053 &
    popd || exit 1
}

GRPC_SERVER_EXAMPLE_VER=20210819

linux_get_dependencies () {
    apt update
    apt install -y cpanminus build-essential libncurses5-dev libreadline-dev libssl-dev perl libpcre3 libpcre3-dev libldap2-dev
}
