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

set -ex

export_or_prefix() {
    export OPENRESTY_PREFIX="/usr/local/openresty-debug"
}

create_lua_deps() {
    echo "Create lua deps cache"

    make deps
    luarocks install luacov-coveralls --tree=deps --local > build.log 2>&1 || (cat build.log && exit 1)

    sudo rm -rf build-cache/deps
    sudo cp -r deps build-cache/
    sudo cp rockspec/apisix-master-0.rockspec build-cache/
}

before_install() {
    sudo cpanm --notest Test::Nginx >build.log 2>&1 || (cat build.log && exit 1)
}

do_install() {
    export_or_prefix

    wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
    sudo apt-get -y update --fix-missing
    sudo apt-get -y install software-properties-common
    sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
    sudo add-apt-repository -y ppa:longsleep/golang-backports

    sudo apt-get update
    sudo apt-get install openresty-debug lua5.1 liblua5.1-0-dev

    wget https://github.com/luarocks/luarocks/archive/v2.4.4.tar.gz
    tar -xf v2.4.4.tar.gz
    cd luarocks-2.4.4
    ./configure --prefix=/usr > build.log 2>&1 || (cat build.log && exit 1)
    make build > build.log 2>&1 || (cat build.log && exit 1)
    sudo make install > build.log 2>&1 || (cat build.log && exit 1)
    cd ..
    rm -rf luarocks-2.4.4

    sudo luarocks install luacheck > build.log 2>&1 || (cat build.log && exit 1)


    if [ ! -f "build-cache/apisix-master-0.rockspec" ]; then
        create_lua_deps

    else
        src=`md5sum rockspec/apisix-master-0.rockspec | awk '{print $1}'`
        src_cp=`md5sum build-cache/apisix-master-0.rockspec | awk '{print $1}'`
        if [ "$src" = "$src_cp" ]; then
            echo "Use lua deps cache"
            sudo cp -r build-cache/deps ./
        else
            create_lua_deps
        fi
    fi

    # sudo apt-get install tree -y
    # tree deps

    git clone https://github.com/iresty/test-nginx.git test-nginx
    make utils

    git clone https://github.com/apache/openwhisk-utilities.git .travis/openwhisk-utilities
    cp .travis/ASF* .travis/openwhisk-utilities/scancode/

    ls -l ./
}

script() {
    export_or_prefix
    export PATH=$OPENRESTY_PREFIX/nginx/sbin:$OPENRESTY_PREFIX/luajit/bin:$OPENRESTY_PREFIX/bin:$PATH
    openresty -V
    sudo service etcd stop
    mkdir -p ~/etcd-data
    /usr/bin/etcd --listen-client-urls 'http://0.0.0.0:2379' --advertise-client-urls='http://0.0.0.0:2379' --data-dir ~/etcd-data > /dev/null 2>&1 &
    etcd --version
    sleep 5


    # enable mTLS
    sed  -i 's/\# port_admin: 9180/port_admin: 9180/'  conf/config.yaml
    sed  -i 's/\# https_admin: true/https_admin: true/'  conf/config.yaml
    sed  -i 's/mtls_enable: false/mtls_enable: true/'  conf/config.yaml
    sed  -i 's#admin_ssl_ca_cert: ""#admin_ssl_ca_cert: "../t/certs/mtls_ca.crt"#'  conf/config.yaml
    sed  -i 's#admin_ssl_cert_key: ""#admin_ssl_cert_key: "../t/certs/mtls_server.key"#'  conf/config.yaml
    sed  -i 's#admin_ssl_cert: ""#admin_ssl_cert: "../t/certs/mtls_server.crt"#'  conf/config.yaml

    ./bin/apisix help
    ./bin/apisix init
    ./bin/apisix init_etcd
    ./bin/apisix start

    sleep 1
    cat logs/error.log


    echo "127.0.0.1 admin.apisix.dev" | sudo tee -a /etc/hosts

    # correct certs
    code=$(curl -i -o /dev/null -s -w %{http_code}  --cacert ./t/certs/mtls_ca.crt --key ./t/certs/mtls_client.key --cert ./t/certs/mtls_client.crt -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' https://admin.apisix.dev:9180/apisix/admin/routes)
    if [ ! $code -eq 200 ]; then
        echo "failed: failed to enabled mTLS for admin"
        exit 1
    fi

    # # no certs
    # code=$(curl -i -o /dev/null -s -w %{http_code} -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' https://admin.apisix.dev:9180/apisix/admin/routes)
    # if [ ! $code -eq 000 ]; then
    #     echo "failed: failed to enabled mTLS for admin"
    #     exit 1
    # fi

    # # no ca cert
    # code=$(curl -i -o /dev/null -s -w %{http_code} --key ./t/certs/mtls_client.key --cert ./t/certs/mtls_client.crt -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' https://admin.apisix.dev:9180/apisix/admin/routes)
    # if [ ! $code -eq 000 ]; then
    #     echo "failed: failed to enabled mTLS for admin"
    #     exit 1
    # fi

    # # error key
    # code=$(curl -i -o /dev/null -s -w %{http_code}  --cacert ./t/certs/mtls_ca.crt --key ./t/certs/mtls_server.key --cert ./t/certs/mtls_client.crt -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' https://admin.apisix.dev:9180/apisix/admin/routes)
    # if [ ! $code -eq 000 ]; then
    #     echo "failed: failed to enabled mTLS for admin"
    #     exit 1
    # fi

    # skip
    code=$(curl -i -o /dev/null -s -w %{http_code} -k -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' https://admin.apisix.dev:9180/apisix/admin/routes)
    if [ ! $code -eq 400 ]; then
        echo "failed: failed to enabled mTLS for admin"
        exit 1
    fi

    ./bin/apisix stop
    sleep 1

    make lint && make license-check || exit 1
}

after_success() {
    cat luacov.stats.out
    luacov-coveralls
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
