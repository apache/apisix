#!/usr/bin/env bash

### BEGIN ###
# Author: idevz
# Since: 08:52:47 2019/07/08
# Description:       travis_runner_osx.sh
# travis_runner_osx  ./travis_runner_osx.sh
#
# Environment variables that control this script:
#
### END ###

set -ex

export_or_prefix() {
    export OPENRESTY_PREFIX=$(brew --prefix openresty/brew/openresty-debug)
}

before_install() {
    HOMEBREW_NO_AUTO_UPDATE=1 brew install perl cpanminus etcd luarocks openresty/brew/openresty-debug redis
    brew upgrade go

    sudo sed -i "" "s/requirepass/#requirepass/g" /usr/local/etc/redis.conf
    brew services start redis

    export GO111MOUDULE=on
    sudo cpanm --notest Test::Nginx >build.log 2>&1 || (cat build.log && exit 1)
    export_or_prefix
    luarocks install --lua-dir=${OPENRESTY_PREFIX}/luajit luacov-coveralls --local --tree=deps
}

do_install() {
    export_or_prefix

    make dev
    make dev_r3

    git clone https://github.com/iresty/test-nginx.git test-nginx
    git clone https://github.com/iresty/grpc_server_example.git grpc_server_example

    wget -P utils https://raw.githubusercontent.com/openresty/openresty-devel-utils/master/lj-releng
	chmod a+x utils/lj-releng

    cd grpc_server_example/
    go build -o grpc_server_example main.go
    cd ..
}

script() {
    export_or_prefix
    export PATH=$OPENRESTY_PREFIX/nginx/sbin:$OPENRESTY_PREFIX/luajit/bin:$OPENRESTY_PREFIX/bin:$PATH

    etcd --enable-v2=true &
    sleep 1

    luarocks install luacheck

    sudo cpanm Test::Nginx

    ./grpc_server_example/grpc_server_example &

    make help
    make init
    sudo make run
    mkdir -p logs
    sleep 1
    sudo make stop

    sleep 1
    make check || exit 1

    ln -sf $PWD/deps/lib $PWD/deps/lib64
    sudo mkdir -p /usr/local/var/log/nginx/
    sudo touch /usr/local/var/log/nginx/error.log
    sudo chmod 777 /usr/local/var/log/nginx/error.log
    APISIX_ENABLE_LUACOV=1 prove -Itest-nginx/lib -I./ -r t
}

after_success() {
    $PWD/deps/bin/luacov-coveralls
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
