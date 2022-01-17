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
    cd ../
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
    (install_stap_tools)
        install_stap_tools
        ;;
    (run_perf_test)
        run_perf_test
        ;;
esac
