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
    export APISIX_MAIN="https://raw.githubusercontent.com/apache/incubator-apisix/master/rockspec/apisix-master-0.rockspec"
}

do_install() {
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

    sudo rm -rf /usr/local/apisix

    # install APISIX by shell
    sudo mkdir -p /usr/local/apisix/deps
    sudo PATH=$PATH ./utils/install-apisix.sh install > build.log 2>&1 || (cat build.log && exit 1)

    sudo PATH=$PATH apisix help
    sudo PATH=$PATH apisix init
    sudo PATH=$PATH apisix start
    sudo PATH=$PATH apisix stop

    sudo PATH=$PATH ./utils/install-apisix.sh remove > build.log 2>&1 || (cat build.log && exit 1)

    # install APISIX by luarocks
    sudo luarocks install $APISIX_MAIN > build.log 2>&1 || (cat build.log && exit 1)

    # show install files
    luarocks show apisix

    sudo PATH=$PATH apisix help
    sudo PATH=$PATH apisix init
    sudo PATH=$PATH apisix start
    sudo PATH=$PATH apisix stop

    # apisix cli test
    sudo PATH=$PATH .travis/apisix_cli_test.sh

    cat /usr/local/apisix/logs/error.log | grep '\[error\]' > /tmp/error.log | true
    if [ -s /tmp/error.log ]; then
        echo "=====found error log====="
        cat /usr/local/apisix/logs/error.log
        exit 1
    fi
}

case_opt=$1
shift

case ${case_opt} in
do_install)
    do_install "$@"
    ;;
script)
    script "$@"
    ;;
esac
