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

# you might need sudo to run this script
if [ -z ${OPENRESTY_PREFIX} ]; then
    OPENRESTY_PREFIX="/usr/local/openresty"
fi

wget https://github.com/luarocks/luarocks/archive/v3.4.0.tar.gz
tar -xf v3.4.0.tar.gz
cd luarocks-3.4.0 || exit

OR_BIN="$OPENRESTY_PREFIX/bin/openresty"
OR_VER=$($OR_BIN -v 2>&1 | awk -F '/' '{print $2}' | awk -F '.' '{print $1"."$2}')
if [[ -e $OR_BIN && "$OR_VER" == 1.19 ]]; then
    WITH_LUA_OPT="--with-lua=${OPENRESTY_PREFIX}/luajit"
else
    # For old version OpenResty, we still need to install LuaRocks with Lua
    WITH_LUA_OPT=
fi

./configure $WITH_LUA_OPT \
    > build.log 2>&1 || (cat build.log && exit 1)

make build > build.log 2>&1 || (cat build.log && exit 1)
sudo make install > build.log 2>&1 || (cat build.log && exit 1)
cd .. || exit
rm -rf luarocks-3.4.0

mkdir ~/.luarocks || true

# OpenResty 1.17.8 or higher version uses openssl111 as the openssl dirname.
OPENSSL_PREFIX=${OPENRESTY_PREFIX}/openssl
if [ -d ${OPENRESTY_PREFIX}/openssl111 ]; then
    OPENSSL_PREFIX=${OPENRESTY_PREFIX}/openssl111
fi

luarocks config variables.OPENSSL_LIBDIR ${OPENSSL_PREFIX}/lib
luarocks config variables.OPENSSL_INCDIR ${OPENSSL_PREFIX}/include
