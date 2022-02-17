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

install_dependencies() {
    apt-get -y update --fix-missing
    apt-get -y install lua5.1 liblua5.1-0-dev
    curl https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh -sL | bash -
    luarocks install ldoc
}

generate_docs() {
    rm -rf autodocs/output || true
    mkdir autodocs/output || true
    cd autodocs/output
    ldoc -c ../config.ld ../../apisix/core/request.lua
    ldoc -c ../config.ld ../../apisix/core/id.lua

    cd ../
    tar -zcvf pdk.tar.gz output
}

case_opt=$1
case $case_opt in
    (install_dependencies)
        install_dependencies
        ;;
    (generate_docs)
        generate_docs
        ;;
esac
