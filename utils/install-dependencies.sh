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

function detect_aur_helper() {
    if [[ $(command -v yay) ]]; then
        AUR_HELPER=yay
    elif [[ $(command -v pacaur) ]]; then
        AUR_HELPER=pacaur
    else
        echo No available AUR helpers found. Please specify your AUR helper by AUR_HELPER.
        exit 255
    fi
}

function install_dependencies_with_aur() {
    detect_aur_helper
    $AUR_HELPER -S openresty --noconfirm
    sudo pacman -S openssl --noconfirm

    export OPENRESTY_PREFIX=/opt/openresty

    sudo mkdir $OPENRESTY_PREFIX/openssl
    sudo ln -s /usr/include $OPENRESTY_PREFIX/openssl/include
    sudo ln -s /usr/lib $OPENRESTY_PREFIX/openssl/lib
}

# Install dependencies on centos and fedora
function install_dependencies_with_yum() {
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo "https://openresty.org/package/${1}/openresty.repo"
    if [[ "${1}" == "centos" ]]; then
        sudo yum -y install centos-release-scl
        sudo yum -y install devtoolset-9 patch wget
        set +eu
        source scl_source enable devtoolset-9
        set -eu
    fi
    sudo yum install -y  \
        gcc gcc-c++ curl wget unzip xz gnupg perl-ExtUtils-Embed cpanminus patch libyaml-devel \
        perl perl-devel pcre pcre-devel openldap-devel \
        openresty-zlib-devel openresty-pcre-devel
}

# Install dependencies on ubuntu and debian
function install_dependencies_with_apt() {
    # add OpenResty source
    sudo apt-get update
    sudo apt-get -y install software-properties-common wget lsb-release gnupg patch
    wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
    arch=$(uname -m | tr '[:upper:]' '[:lower:]')
    arch_path=""
    if [[ $arch == "arm64" ]] || [[ $arch == "aarch64" ]]; then
        arch_path="arm64/"
    fi
    if [[ "${1}" == "ubuntu" ]]; then
        sudo add-apt-repository -y "deb http://openresty.org/package/${arch_path}ubuntu $(lsb_release -sc) main"
    elif [[ "${1}" == "debian" ]]; then
        sudo add-apt-repository -y "deb http://openresty.org/package/${arch_path}debian $(lsb_release -sc) openresty"
    fi
    sudo apt-get update

    # install some compilation tools
    sudo apt-get install -y curl make gcc g++ cpanminus libpcre3 libpcre3-dev libldap2-dev unzip openresty-zlib-dev openresty-pcre-dev
}

# Identify the different distributions and call the corresponding function
function multi_distro_installation() {
    if grep -Eqi "CentOS" /etc/issue || grep -Eq "CentOS" /etc/*-release; then
        install_dependencies_with_yum "centos"
    elif grep -Eqi -e "Red Hat" -e "rhel" /etc/*-release; then
        install_dependencies_with_yum "rhel"
    elif grep -Eqi "Fedora" /etc/issue || grep -Eq "Fedora" /etc/*-release; then
        install_dependencies_with_yum "fedora"
    elif grep -Eqi "Debian" /etc/issue || grep -Eq "Debian" /etc/*-release; then
        install_dependencies_with_apt "debian"
    elif grep -Eqi "Ubuntu" /etc/issue || grep -Eq "Ubuntu" /etc/*-release; then
        install_dependencies_with_apt "ubuntu"
    elif grep -Eqi "Arch" /etc/issue || grep -Eqi "EndeavourOS" /etc/issue || grep -Eq "Arch" /etc/*-release; then
        install_dependencies_with_aur
    else
        echo "Non-supported distribution, APISIX is only supported on Linux-based systems"
        exit 1
    fi
    install_apisix_runtime
}

function multi_distro_uninstallation() {
    if grep -Eqi "CentOS" /etc/issue || grep -Eq "CentOS" /etc/*-release; then
        sudo yum autoremove -y openresty-zlib-devel openresty-pcre-devel
    elif grep -Eqi -e "Red Hat" -e "rhel" /etc/*-release; then
        sudo yum autoremove -y openresty-zlib-devel openresty-pcre-devel
    elif grep -Eqi "Fedora" /etc/issue || grep -Eq "Fedora" /etc/*-release; then
        sudo yum autoremove -y openresty-zlib-devel openresty-pcre-devel
    elif grep -Eqi "Debian" /etc/issue || grep -Eq "Debian" /etc/*-release; then
        sudo apt-get autoremove -y openresty-zlib-dev openresty-pcre-dev
    elif grep -Eqi "Ubuntu" /etc/issue || grep -Eq "Ubuntu" /etc/*-release; then
        sudo apt-get autoremove -y openresty-zlib-dev openresty-pcre-dev
    else
        echo "Non-supported distribution, APISIX is only supported on Linux-based systems"
        exit 1
    fi
}

function install_apisix_runtime() {
    export runtime_version=${APISIX_RUNTIME:?}
    wget "https://raw.githubusercontent.com/api7/apisix-build-tools/apisix-runtime/${APISIX_RUNTIME}/build-apisix-runtime.sh"
    chmod +x build-apisix-runtime.sh
    ./build-apisix-runtime.sh latest
    rm build-apisix-runtime.sh
}

# Install LuaRocks
function install_luarocks() {
    if [ -f "./utils/linux-install-luarocks.sh" ]; then
        ./utils/linux-install-luarocks.sh
    elif [ -f "./linux-install-luarocks.sh" ]; then
        ./linux-install-luarocks.sh
    else
        echo "Installing luarocks from remote master branch"
        curl https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh -sL | bash -
    fi
}

# Entry
function main() {
    OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
    if [[ "$#" == 0 ]]; then
        if [[ "${OS_NAME}" == "linux" ]]; then
            multi_distro_installation
            install_luarocks
            return
        else
            echo "Non-supported distribution, APISIX is only supported on Linux-based systems"
            exit 1
        fi
    fi

    case_opt=$1
    case "${case_opt}" in
        "install_luarocks")
            install_luarocks
        ;;
        "uninstall")
            if [[ "${OS_NAME}" == "linux" ]]; then
                multi_distro_uninstallation
            else
                echo "Non-supported distribution, APISIX is only supported on Linux-based systems"
            fi
        ;;
        *)
            echo "Unsupported method: ${case_opt}"
        ;;
    esac
}

main "$@"
