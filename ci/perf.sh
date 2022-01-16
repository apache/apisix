. ./ci/common.sh

install_dependencies() {
  create_lua_deps
  apt-get -y update --fix-missing
  apt-get -y install lua5.1 liblua5.1-0-dev
  bash utils/install-dependencies.sh install_luarocks
  bash utils/install-dependencies.sh install_luarocks
  bash utils/install-dependencies.sh multi_distro_installation
}

install_wrk2() {
  cd ..
  git clone https://github.com/giltene/wrk2
  cd wrk2 || true
  apt-get install -y openssl libssl-dev libz-dev
  make
  ln -s $PWD/wrk /usr/bin
  cd ..
}

run_perf_test() {
  pip3 install -r t/perf/requirements.txt --user
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
