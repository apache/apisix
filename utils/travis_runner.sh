#!/usr/bin/env bash

### BEGIN ###
# Author: idevz
# Since: 08:52:47 2019/07/08
# Description:       travis_runner.sh
# travis_runner          ./travis_runner.sh
#
# Environment variables that control this script:
#
### END ###

set -ex

export_or_prefix() {
    if [ $TRAVIS_OS_NAME = osx ]; then
        export OPENRESTY_PREFIX=$(TMP='./v_tmp' && $(which openresty) -V &>${TMP} &&
            cat ${TMP} | grep prefix | grep -Eo 'prefix=(.*?)/nginx' |
            grep -Eo '/.*/' && rm ${TMP})
    else
        export OPENRESTY_PREFIX="/usr/local/openresty-debug"
    fi
}

before_install() {
    if [ $TRAVIS_OS_NAME = osx ]; then
        HOMEBREW_NO_AUTO_UPDATE=1 brew install perl cpanminus etcd luarocks openresty/brew/openresty-debug
    fi
    sudo cpanm --notest Test::Nginx IPC::Run >build.log 2>&1 || (cat build.log && exit 1)
}

do_install() {
    if [ ! $TRAVIS_OS_NAME = osx ]; then
        wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
        sudo apt-get -y install software-properties-common
        sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
        sudo apt-get update
        sudo apt-get install openresty-debug
    fi

    export_or_prefix

    luarocks install --lua-dir=${OPENRESTY_PREFIX}luajit luacov-coveralls --local --tree=deps

    if [ $TRAVIS_OS_NAME = osx ]; then
        make dev
    else
        sudo luarocks install --lua-dir=${OPENRESTY_PREFIX}luajit apisix-*.rockspec --only-deps
    fi

    git clone https://github.com/openresty/test-nginx.git test-nginx
}

script() {
    export_or_prefix
    export PATH=$OPENRESTY_PREFIX/nginx/sbin:$OPENRESTY_PREFIX/luajit/bin:$OPENRESTY_PREFIX/bin:$PATH
    if [ $TRAVIS_OS_NAME = osx ]; then
        luarocks install luacheck
        brew services start etcd
        make help
        make init
        sudo make run
        mkdir -p logs
        sleep 1
        sudo make stop

        sudo cpanm Test::Nginx

        sleep 1
        make check || exit 1

        ln -sf $PWD/deps/lib $PWD/deps/lib64
        sudo mkdir -p /usr/local/var/log/nginx/
        sudo touch /usr/local/var/log/nginx/error.log
        sudo chmod 777 /usr/local/var/log/nginx/error.log
        APISIX_ENABLE_LUACOV=1 prove -Itest-nginx/lib -I./ -r -v t
        cat $PWD/t/servroot/conf/nginx.conf
        cat /usr/local/var/log/nginx/error.log
    else
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
    fi
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
