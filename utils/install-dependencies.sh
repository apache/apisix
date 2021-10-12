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

# Install dependencies on centos
function install_dependencies_on_centos() {
    # add OpenResty source
    sudo yum install yum-utils
    sudo yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo

    # install OpenResty and some compilation tools
    sudo yum install -y openresty curl git gcc openresty-openssl111-devel unzip pcre pcre-devel

    # install LuaRocks
    curl https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh -sL | bash -

}

# Install dependencies on fedora
function install_dependencies_on_fedora() {
    # add OpenResty source
    sudo yum install yum-utils
    sudo yum-config-manager --add-repo https://openresty.org/package/fedora/openresty.repo

    # install OpenResty and some compilation tools
    sudo yum install -y openresty curl git gcc openresty-openssl111-devel pcre pcre-devel

    # install LuaRocks
    curl https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh -sL | bash -
  
}

# Install dependencies on ubuntu
function install_dependencies_on_ubuntu() {
    # add OpenResty source
    sudo apt-get update
    sudo apt-get -y install software-properties-common wget
    wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
    sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
    sudo apt-get update

    # install OpenResty and some compilation tools
    sudo apt-get install -y git openresty curl openresty-openssl111-dev make gcc libpcre3 libpcre3-dev

    # install OpenResty and some compilation tools
    curl https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh -sL | bash -
}

# Install dependencies on debian
function install_dependencies_on_debian() {
    # add OpenResty source
    sudo apt-get update
    sudo apt-get -y install wget
    wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
    sudo apt-get -y install software-properties-common
    sudo add-apt-repository -y "deb http://openresty.org/package/debian $(lsb_release -sc) openresty"
    sudo apt-get update

    # install OpenResty and some compilation tools
    sudo apt-get install -y git openresty curl make openresty-openssl111-dev libpcre3 libpcre3-dev

    # install LuaRocks
    curl https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh -sL | bash -
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
        install_dependencies_on_centos
    elif grep -Eqi "Fedora" /etc/issue || grep -Eq "Fedora" /etc/*-release; then
        install_dependencies_on_fedora
    elif grep -Eqi "Debian" /etc/issue || grep -Eq "Debian" /etc/*-release; then
        install_dependencies_on_debian
    elif grep -Eqi "Ubuntu" /etc/issue || grep -Eq "Ubuntu" /etc/*-release; then
        install_dependencies_on_ubuntu
    else
        echo "Non-supported operating system version"
    fi
}

# Install etcd
function install_etcd() {
    wget https://github.com/etcd-io/etcd/releases/download/v3.4.13/etcd-v3.4.13-linux-amd64.tar.gz
    tar -xvf etcd-v3.4.13-linux-amd64.tar.gz && \
        cd etcd-v3.4.13-linux-amd64 && \
        sudo cp -a etcd etcdctl /usr/bin/
    nohup etcd &
}

# Entry
function main() {  
    a=`uname -s`
    if [[ ${a} == "Linux" ]]; then
        multi_distro_installation
        install_etcd
    elif [[ ${a} == "Darwin" ]]; then
        install_dependencies_on_mac_osx
    else
        echo "Non-surported distribution"
    fi
}

main
