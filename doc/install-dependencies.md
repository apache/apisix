# Install Dependencies

* [CentOS 7](#centos-7)
* [Ubuntu 18.04](#ubuntu-1804)
* [Debian 9](#debian-9)
* [CentOS 6](#centos-6)

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
sudo yum install -y etcd openresty curl git automake autoconf \
    gcc pcre-devel libtool gcc-c++ luarocks cmake3 lua-devel

sudo ln -s /usr/bin/cmake3 /usr/bin/cmake

# start etcd server
sudo service etcd start
```

Ubuntu 18.04
============

```shell
# add openresty source
wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
sudo apt-get -y install software-properties-common
sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
sudo apt-get update

# install openresty, etcd and some compilation tools
sudo apt-get install -y git etcd openresty curl luarocks\
    check libpcre3 libpcre3-dev libjemalloc-dev \
    libjemalloc1 build-essential libtool automake autoconf pkg-config cmake

# start etcd server
sudo service etcd start
```

Debian 9
========

```shell
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
sudo apt-get install -y git openresty cmake curl luarocks\
    check libpcre3 libpcre3-dev libjemalloc-dev \
    libjemalloc1 build-essential libtool automake autoconf pkg-config

# start etcd server
nohup etcd &
```

CentOS 6
========

TODO

The compilation of `libr3` relies on later versions of `autoconf` and `pcre`, but the CentOS 6 comes with a lower version, will support CentOS 6 later.
