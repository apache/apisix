#!/bin/sh

set -ex

OR_EXEC=`which openresty 2>&1`
echo $OR_EXEC

# check the openresty exist
CHECK_OR_EXIST=`echo $OR_EXEC | grep ": no openresty" | wc -l`
if [ $CHECK_OR_EXIST -eq 1 ];then
      echo "can not find the openresty, install failed"
      exit 1;
fi

LUA_JIT_DIR=`$OR_EXEC -V 2>&1 | grep prefix | grep -Eo 'prefix=(.*?)/nginx' | grep -Eo '/.*/'`
LUA_JIT_DIR="${LUA_JIT_DIR}luajit"
echo $LUA_JIT_DIR

LUAROCKS_VER=`luarocks --version | grep -E -o  "luarocks [0-9]+."`
echo $LUAROCKS_VER

UNAME=`uname`
echo $UNAME


do_install() {
    if [ "$UNAME" == "Darwin" ]; then
        luarocks install --lua-dir=$LUA_JIT_DIR apisix --tree=/usr/local/apisix/deps --local

    elif [ "$LUAROCKS_VER" == 'luarocks 3.' ]; then
        luarocks install --lua-dir=$LUA_JIT_DIR apisix --tree=/usr/local/apisix/deps --local

    else
        luarocks install apisix --tree=/usr/local/apisix/deps --local
    fi

    sudo rm -f /usr/local/bin/apisix
    sudo ln -s /usr/local/apisix/deps/bin/apisix /usr/local/bin/apisix
}


do_remove() {
    sudo rm -f /usr/local/bin/apisix
    luarocks purge /usr/local/apisix/deps --tree=/usr/local/apisix/deps
}


case_opt=$1
if [ ! $case_opt ]; then
    case_opt='install'
fi
echo $case_opt

case ${case_opt} in
install)
    do_install "$@"
    ;;
remove)
    do_remove "$@"
    ;;
esac
