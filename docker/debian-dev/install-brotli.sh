install_brotli () {
    apt-get -qy update
    apt-get install -y sudo cmake wget unzip
    local BORTLI_VERSION="1.1.0"
    wget -q https://github.com/google/brotli/archive/refs/tags/v${BORTLI_VERSION}.zip || exit -1 
    unzip v${BORTLI_VERSION}.zip && cd ./brotli-${BORTLI_VERSION} && mkdir build && cd build || exit -1 
    local CMAKE=$(command -v cmake3 > /dev/null 2>&1 && echo cmake3 || echo cmake) || exit -1 
    ${CMAKE} -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local/brotli .. || exit -1 
    sudo ${CMAKE} --build . --config Release --target install || exit -1
    if [ -d "/usr/local/brotli/lib64" ]; then
        echo /usr/local/brotli/lib64 | sudo tee /etc/ld.so.conf.d/brotli.conf
    else
        echo /usr/local/brotli/lib | sudo tee /etc/ld.so.conf.d/brotli.conf
    fi
    sudo ldconfig || exit -1
    ln -sf /usr/local/brotli/bin/brotli /usr/bin/brotli
    cd ../..
    rm -rf brotli-${BORTLI_VERSION}
    rm -rf /v${BORTLI_VERSION}.zip
    export SUDO_FORCE_REMOVE=yes
    apt purge -qy cmake sudo wget unzip
    apt-get remove --purge --auto-remove -y
}
install_brotli
