#!/usr/bin/env bash

### BEGIN ###
# Author: idevz
# Since: 08:52:47 2019/07/08
# Description:         travis_runnerz_linux.sh
# travis_runner_linux  ./travis_runner_linux.sh
#
# Environment variables that control this script:
#
### END ###

set -ex

export_or_prefix() {
    export OPENRESTY_PREFIX="/usr/local/openresty-debug"
}

before_install() {
    sudo cpanm --notest Test::Nginx IPC::Run >build.log 2>&1 || (cat build.log && exit 1)
    sudo luarocks install --lua-dir=/usr/local/openresty/luajit luacov-coveralls
}

do_install() {
    wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
    sudo apt-get -y install software-properties-common
    sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
    sudo apt-get update
    sudo apt-get install openresty-debug

    export_or_prefix

    sudo luarocks install --lua-dir=${OPENRESTY_PREFIX}luajit apisix-*.rockspec --only-deps

    git clone https://github.com/openresty/test-nginx.git test-nginx
}

script() {
    export_or_prefix
    export PATH=$OPENRESTY_PREFIX/nginx/sbin:$OPENRESTY_PREFIX/luajit/bin:$OPENRESTY_PREFIX/bin:$PATH
    sudo service etcd start
    ./bin/apisix help
    ./bin/apisix init
    ./bin/apisix init_etcd
    ./bin/apisix start
    mkdir -p logs
    sleep 1
    ./bin/apisix stop
    sleep 1
    make check || exit 1
    APISIX_ENABLE_LUACOV=1 prove -Itest-nginx/lib -r t
}

after_success() {
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
