#!/bin/sh

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

OR_EXEC=`which openresty 2>&1`
echo $OR_EXEC
APISIX_VER="https://raw.githubusercontent.com/apache/incubator-apisix/master/rockspec/apisix-master-0.rockspec"

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
    if [ "$UNAME" = "Darwin" ]; then
        luarocks install --lua-dir=$LUA_JIT_DIR $APISIX_VER --tree=/usr/local/apisix/deps --local

    elif [ "$LUAROCKS_VER" = 'luarocks 3.' ]; then
        luarocks install --lua-dir=$LUA_JIT_DIR $APISIX_VER --tree=/usr/local/apisix/deps --local

    else
        luarocks install $APISIX_VER --tree=/usr/local/apisix/deps --local
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
