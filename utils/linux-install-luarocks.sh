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

if [ -z ${OR_PREFIX} ]; then
    OR_PREFIX="/usr/local/openresty"
fi

wget https://github.com/luarocks/luarocks/archive/v3.4.0.tar.gz
tar -xf v3.4.0.tar.gz
cd luarocks-3.4.0 || exit
./configure --prefix=/usr > build.log 2>&1 || (cat build.log && exit 1)
make build > build.log 2>&1 || (cat build.log && exit 1)
make install > build.log 2>&1 || (cat build.log && exit 1)
cd .. || exit
rm -rf luarocks-3.4.0

mkdir ~/.luarocks || true
luarocks config variables.OPENSSL_LIBDIR ${OR_PREFIX}/openssl/lib
luarocks config variables.OPENSSL_INCDIR ${OR_PREFIX}/openssl/include
