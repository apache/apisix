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

. ./ci/common.sh

set -ex

install_dependencies() {
    apt-get -y update --fix-missing
    apt-get -y install lua5.1 liblua5.1-0-dev
    export_or_prefix
    export OPENRESTY_VERSION=source
    ./ci/linux-install-openresty.sh
    bash utils/install-dependencies.sh install_luarocks
    make deps
}

install_wrk2() {
    cd ..
    git clone https://github.com/giltene/wrk2
    cd wrk2 || true
    make
    ln -s $PWD/wrk /usr/bin
    cd ..
}

install_stap_tools() {
    # install ddeb source repo
    sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys C8CAB6595FDFF622

    codename=$(lsb_release -c | awk  '{print $2}')
    sudo tee /etc/apt/sources.list.d/ddebs.list << EOF
    deb http://ddebs.ubuntu.com/ ${codename}      main restricted universe multiverse
    deb http://ddebs.ubuntu.com/ ${codename}-updates  main restricted universe multiverse
    deb http://ddebs.ubuntu.com/ ${codename}-proposed main restricted universe multiverse
EOF

    sudo apt-get update
    sudo apt-get install linux-image-$(uname -r)-dbgsym
    sudo apt install elfutils libdw-dev
    sudo apt-get install -y python3-setuptools python3-wheel

    # install systemtap
    cd /usr/local/
    wget -q http://sourceware.org/systemtap/ftp/releases/systemtap-4.6.tar.gz
    tar -zxf systemtap-4.6.tar.gz
    mv systemtap-4.6 systemtap
    cd systemtap
    ./configure && make all && sudo make install &&  stap --version
    cd ..

    # see https://github.com/openresty/stapxx/pull/48
    git clone https://github.com/api7/stapxx.git -b luajit-gc64
    git clone https://github.com/openresty/openresty-systemtap-toolkit.git
    git clone https://github.com/brendangregg/FlameGraph.git
}


run_performance_test() {
    sudo chmod -R 777 ./
    ulimit -n 10240

    pip3 install -r t/perf/requirements.txt --user

    #openresty-debug
    export OPENRESTY_PREFIX="/usr/local/openresty"
    export PATH=$OPENRESTY_PREFIX/nginx/sbin:$OPENRESTY_PREFIX/bin:$OPENRESTY_PREFIX/luajit/bin:$PATH

    mkdir output
    python3 ./t/perf/test_http.py >$PWD/output/performance.txt 2>&1 &

    sleep 1

    # stapxx
    export STAP_PLUS_HOME=/usr/local/stapxx
    export PATH=/usr/local/stapxx:/usr/local/stapxx/samples:$PATH
    # openresty-systemtap-toolkit
    export PATH=/usr/local/openresty-systemtap-toolkit:$PATH
    # FlameGraph
    export PATH=/usr/local/FlameGraph:$PATH

    sudo env PATH=$PATH /usr/local/stapxx/samples/lj-lua-stacks.sxx --arg time=30 --skip-badvars -x $(pgrep -P $(cat logs/nginx.pid) -n -f worker) > /tmp/tmp.bt
    sudo env PATH=$PATH /usr/local/openresty-systemtap-toolkit/fix-lua-bt /tmp/tmp.bt > /tmp/flame.bt
    sudo env PATH=$PATH /usr/local/FlameGraph/stackcollapse-stap.pl /tmp/flame.bt > /tmp/flame.cbt
    sudo env PATH=$PATH /usr/local/FlameGraph/flamegraph.pl /tmp/flame.cbt > $PWD/output/flamegraph.svg
}

case_opt=$1
case $case_opt in
    (install_dependencies)
        install_dependencies
        ;;
    (install_wrk2)
        install_wrk2
        ;;
    (install_stap_tools)
        install_stap_tools
        ;;
    (run_performance_test)
        run_performance_test
        ;;
esac
