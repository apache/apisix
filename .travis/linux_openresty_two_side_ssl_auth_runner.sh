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
    sudo service etcd start

    mv ./conf/config-for-two-side-ssl-auth.yaml ./conf/config.yaml

    ./bin/apisix help
    ./bin/apisix init
    ./bin/apisix init_etcd
    ./bin/apisix start

    sleep 1
    cat logs/error.log


    sudo echo '127.0.0.1 nginx.test.com' > /etc/hosts
    curl --cacert ./conf/cert/apisix_admin_ca.crt --key ./conf/cert/apisix_admin_client.key --cert ./conf/cert/apisix_admin_client.crt  https://nginx.test.com:9180/apisix/admin/ssls

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
