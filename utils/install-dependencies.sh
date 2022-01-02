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
    if [[ $(which yay) ]]; then
        AUR_HELPER=yay
    elif [[ $(which pacaur) ]]; then
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

    local common_dep="curl git gcc openresty-openssl111-devel unzip pcre pcre-devel openldap-devel"
    if [ "${1}" == "centos" ]; then
        # add APISIX source
        sudo yum install -y https://repos.apiseven.com/packages/centos/apache-apisix-repo-1.0-1.noarch.rpm

        # install apisix-base and some compilation tools
        # shellcheck disable=SC2086
        sudo yum install -y apisix-base $common_dep
    else
        # add OpenResty source
        sudo yum-config-manager --add-repo "https://openresty.org/package/${1}/openresty.repo"

        # install OpenResty and some compilation tools
        # shellcheck disable=SC2086
        sudo yum install -y openresty $common_dep
    fi
}

# Install dependencies on ubuntu and debian
function install_dependencies_with_apt() {
    # add OpenResty source
    sudo apt-get update
    sudo apt-get -y install software-properties-common wget lsb-release
    wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
    if [[ "${1}" == "ubuntu" ]]; then
        sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
    elif [[ "${1}" == "debian" ]]; then
        sudo add-apt-repository -y "deb http://openresty.org/package/debian $(lsb_release -sc) openresty"
    fi
    sudo apt-get update

    # install OpenResty and some compilation tools
    sudo apt-get install -y git openresty curl openresty-openssl111-dev make gcc libpcre3 libpcre3-dev libldap2-dev
}

# Install dependencies on mac osx
function install_dependencies_on_mac_osx() {
    # install OpenResty, etcd and some compilation tools
    brew install openresty/brew/openresty luarocks lua@5.1 etcd curl git pcre openldap

    # start etcd server
    brew services start etcd
}

# Identify the different distributions and call the corresponding function
function multi_distro_installation() {
    if grep -Eqi "CentOS" /etc/issue || grep -Eq "CentOS" /etc/*-release; then
        install_dependencies_with_yum "centos"
    elif grep -Eqi "Fedora" /etc/issue || grep -Eq "Fedora" /etc/*-release; then
        install_dependencies_with_yum "fedora"
    elif grep -Eqi "Debian" /etc/issue || grep -Eq "Debian" /etc/*-release; then
        install_dependencies_with_apt "debian"
    elif grep -Eqi "Ubuntu" /etc/issue || grep -Eq "Ubuntu" /etc/*-release; then
        install_dependencies_with_apt "ubuntu"
    elif grep -Eqi "Arch" /etc/issue || grep -Eq "Arch" /etc/*-release; then
        install_dependencies_with_aur
    else
        echo "Non-supported operating system version"
    fi
}

# Install etcd
function install_etcd() {
    ETCD_VERSION='3.4.13'
    wget https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
    tar -xvf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz && \
        cd etcd-v${ETCD_VERSION}-linux-amd64 && \
        sudo cp -a etcd etcdctl /usr/bin/
    nohup etcd &
}

# Install LuaRocks
function install_luarocks() {
    curl https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh -sL | bash -
}

# Entry
function main() {
    OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
    if [[ "$#" == 0 ]]; then
        if [[ "${OS_NAME}" == "linux" ]]; then
            multi_distro_installation
            install_luarocks
            install_etcd
        elif [[ "${OS_NAME}" == "darwin" ]]; then
            install_dependencies_on_mac_osx
        else
            echo "Non-surported distribution"
        fi
        return
    fi

    case_opt=$1
    case "${case_opt}" in
        "install_etcd")
            install_etcd
        ;;
        "install_luarocks")
            install_luarocks
        ;;
        "multi_distro_installation")
            multi_distro_installation
        ;;
        *)
            echo "Unsupported method: ${case_opt}"
        ;;
    esac
}

main "$@"
