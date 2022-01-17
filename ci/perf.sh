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
    ./utils/linux-install-openresty.sh
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
    wget http://sourceware.org/systemtap/ftp/releases/systemtap-4.6.tar.gz
    tar -zxf systemtap-4.6.tar.gz
    mv systemtap-4.6 systemtap
    cd systemtap
    ./configure && make all && sudo make install &&  stap --version
    cd ..

    git clone https://github.com/openresty/stapxx.git
    git clone https://github.com/openresty/openresty-systemtap-toolkit.git
    git clone https://github.com/brendangregg/FlameGraph.git
}


run_perf_test() {
    # export_prefix
    # stapxx
    export STAP_PLUS_HOME=/usr/local/stapxx
    export PATH=$STAP_PLUS_HOME:$STAP_PLUS_HOME/samples:$PATH
    # openresty-systemtap-toolkit
    export PATH=$PATH:/usr/local/openresty-systemtap-toolkit
    # FlameGraph
    export PATH=$PATH:/usr/local/FlameGraph

    pip3 install -r t/perf/requirements.txt --user
    sudo chmod -R 777 ./
    ulimit -n 10240
    ulimit -n -S
    ulimit -n -H

    python3 ./t/perf/test_http.py >perf.txt 2>&1 &

    master_id=$(cat logs/nginx.pid)
    worker_id=$(pgrep -P $master_id -n -f worker)
    sudo /usr/local/stapxx/samples/lj-lua-stacks.sxx --arg time=5 --skip-badvars -x $(pgrep -P $(cat logs/nginx.pid) -n -f worker) > tmp.bt

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
    (run_perf_test)
        run_perf_test
        ;;
esac
