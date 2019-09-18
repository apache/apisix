#!/usr/bin/env bash

### BEGIN ###
# Author: idevz
# Since: 08:52:47 2019/07/08
# Description:         travis_runnerz_linux.sh
# travis_runner_linux  ./travis_runner_linux.sh
#
# Environment variables that control this script:
# OPENRESTY_PREFIX
### END ###

set -ex

export_or_prefix() {
    export OPENRESTY_PREFIX="/usr/local/openresty-debug"
}

before_install() {
    sudo cpanm --notest Test::Nginx >build.log 2>&1 || (cat build.log && exit 1)
}

do_install() {
    wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
    sudo apt-get -y update --fix-missing
    sudo apt-get -y install software-properties-common
    sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
    sudo add-apt-repository -y ppa:longsleep/golang-backports

    sudo apt-get update

    sudo apt-get install openresty-debug
    sudo luarocks install --lua-dir=${OPENRESTY_PREFIX}/luajit luacov-coveralls

    export GO111MOUDULE=on

    export_or_prefix

    sudo luarocks make --lua-dir=${OPENRESTY_PREFIX}/luajit rockspec/apisix-dev-1.0-0.rockspec --tree=deps --only-deps --local
    sudo luarocks install --lua-dir=${OPENRESTY_PREFIX}/luajit lua-resty-libr3 --tree=deps --local

    git clone https://github.com/iresty/test-nginx.git test-nginx

    ls -l ./
    if [ ! -f "build-cache/grpc_server_example" ]; then
        sudo apt-get install golang

        git clone https://github.com/iresty/grpc_server_example.git grpc_server_example

        cd grpc_server_example/
        go build -o grpc_server_example main.go
        mv grpc_server_example ../build-cache/
        cd ..
    fi

}

script() {
    export_or_prefix
    export PATH=$OPENRESTY_PREFIX/nginx/sbin:$OPENRESTY_PREFIX/luajit/bin:$OPENRESTY_PREFIX/bin:$PATH
    openresty -V
    sudo service etcd start

    ./build-cache/grpc_server_example &

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
