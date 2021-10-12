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

# Install dependencies on centos and fedora
function install_dependencies_on_centos_and_fedora() {
    # add OpenResty source
    sudo yum install yum-utils
    sudo yum-config-manager --add-repo https://openresty.org/package/${DISTRO}/openresty.repo

    # install OpenResty and some compilation tools
    sudo yum install -y openresty curl git gcc openresty-openssl111-devel unzip pcre pcre-devel
}

# Install dependencies on ubuntu and debian
function install_dependencies_on_ubuntu_and_debian() {
    # add OpenResty source
    sudo apt-get update
    sudo apt-get -y install software-properties-common wget
    wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
    if [[ $DISTRO == "ubuntu" ]]; then
        sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
    elif [[ $DISTRO == "debian" ]]; then
        sudo add-apt-repository -y "deb http://openresty.org/package/debian $(lsb_release -sc) openresty"
    fi
    sudo apt-get update

    # install OpenResty and some compilation tools
    sudo apt-get install -y git openresty curl openresty-openssl111-dev make gcc libpcre3 libpcre3-dev
}

# Install dependencies on mac osx
function install_dependencies_on_mac_osx() {
    # install OpenResty, etcd and some compilation tools
    brew install openresty/brew/openresty luarocks lua@5.1 etcd curl git pcre

    # start etcd server
    brew services start etcd
}

# Identify the different distributions and call the corresponding function
function multi_distro_installation() {
    if grep -Eqi "CentOS" /etc/issue || grep -Eq "CentOS" /etc/*-release; then
        DISTRO="centos"
        install_dependencies_on_centos_and_fedora
    elif grep -Eqi "Fedora" /etc/issue || grep -Eq "Fedora" /etc/*-release; then
        DISTRO="fedora"
        install_dependencies_on_centos_and_fedora
    elif grep -Eqi "Debian" /etc/issue || grep -Eq "Debian" /etc/*-release; then
        DISTRO="debian"
        install_dependencies_on_ubuntu_and_debian
    elif grep -Eqi "Ubuntu" /etc/issue || grep -Eq "Ubuntu" /etc/*-release; then
        DISTRO="ubuntu"
        install_dependencies_on_ubuntu_and_debian
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
    if [[ ${OS_NAME} == "linux" ]]; then
        multi_distro_installation
        install_luarocks
        install_etcd
    elif [[ ${OS_NAME} == "darwin" ]]; then
        install_dependencies_on_mac_osx
    else
        echo "Non-surported distribution"
    fi
}

main
