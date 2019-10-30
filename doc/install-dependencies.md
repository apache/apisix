# Install Dependencies

* [CentOS 6](#centos-6)
* [CentOS 7](#centos-7)
* [Ubuntu 16.04 & 18.04](#ubuntu-1604--1804)
* [Debian 9 & 10](#debian-9--10)
* [Mac OSX](#mac-osx)

CentOS 6
========

```shell
# add openresty source
sudo yum install yum-utils
sudo yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo

# install openresty, etcd and some compilation tools
sudo yum install -y openresty curl git gcc luarocks lua-devel make

wget https://github.com/etcd-io/etcd/releases/download/v3.3.13/etcd-v3.3.13-linux-amd64.tar.gz
tar -xvf etcd-v3.3.13-linux-amd64.tar.gz && \
    cd etcd-v3.3.13-linux-amd64 && \
    sudo cp -a etcd etcdctl /usr/bin/

# start etcd server
nohup etcd &
```

CentOS 7
========

```shell
# install epel, `luarocks` need it.
wget http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
sudo rpm -ivh epel-release-latest-7.noarch.rpm

# add openresty source
sudo yum install yum-utils
sudo yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo

# install openresty, etcd and some compilation tools
sudo yum install -y etcd openresty curl git gcc luarocks lua-devel

# start etcd server
sudo service etcd start
```

Ubuntu 16.04 & 18.04
====================

```shell
# add openresty source
wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
sudo apt-get -y install software-properties-common
sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
sudo apt-get update

# install openresty, etcd and some compilation tools
sudo apt-get install -y git etcd openresty curl luarocks 

# start etcd server
sudo service etcd start
```

Debian 9 & 10
=============

```shell
# optional
sed -i 's|^deb http://deb.debian.org/debian|deb http://mirrors.huaweicloud.com/debian|g' /etc/apt/sources.list
sed -i 's|^deb http://security.debian.org/debian-security|deb http://mirrors.huaweicloud.com/debian-security|g' /etc/apt/sources.list
apt update
apt install wget gnupg -y

# add openresty source
wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
sudo apt-get -y install software-properties-common
sudo add-apt-repository -y "deb http://openresty.org/package/debian $(lsb_release -sc) openresty"
sudo apt-get update

# install etcd
wget https://github.com/etcd-io/etcd/releases/download/v3.3.13/etcd-v3.3.13-linux-amd64.tar.gz
tar -xvf etcd-v3.3.13-linux-amd64.tar.gz && \
    cd etcd-v3.3.13-linux-amd64 && \
    sudo cp -a etcd etcdctl /usr/bin/

# install openresty and some compilation tools
sudo apt-get install -y git openresty curl luarocks make

# start etcd server
nohup etcd &
```

Mac OSX
=======

```shell
# install openresty, etcd and some compilation tools
brew install openresty/brew/openresty etcd luarocks curl git

# start etcd server with v2 protocol
etcd --enable-v2=true &
```
