#!/usr/bin/env bash

set -ex

install_dependencies() {
    apt-get -y update --fix-missing
    apt-get -y install lua5.1 liblua5.1-0-dev
    bash utils/install-dependencies.sh multi_distro_installation
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

run_perf_test() {
    sudo apt-get install -y python3-setuptools python3-wheel
    pip3 install -r t/perf/requirements.txt --user
    sudo chmod -R 777 ./
    ulimit -n 10240
    ulimit -n -S
    ulimit -n -H
    python3 ./t/perf/test_http.py
}

case_opt=$1
case $case_opt in
    (install_dependencies)
        install_dependencies
        ;;
    (install_wrk2)
        install_wrk2
        ;;
    (run_perf_test)
        run_perf_test
        ;;
esac
