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

# workdir is the root of the apisix, use command: autodocs/generate.sh build to generate the docs,
# and the output will be in the workdir/autodocs/output/ directory.
build() {
    # install dependencies
    apt-get -y update --fix-missing
    apt-get -y install lua5.1 liblua5.1-0-dev
    curl https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh -sL | bash -
    luarocks install ldoc

    # generate docs
    rm -rf autodocs/output || true
    mkdir autodocs/output || true
    cd autodocs/output
    find ../../apisix/core -name "*.lua" -type f -exec ldoc -c ../config.ld {} \;

    # generate the markdown files' name
    rm ../md_files_name.txt || true
    output="./"
    mds=$(ls $output)
    for md in $mds
    do
       echo $md >> ../md_files_name.txt
    done
}

case_opt=$1
case $case_opt in
    (build)
        build
        ;;
esac
