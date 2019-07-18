[中文](README_CN.md)
## APISIX

[![Build Status](https://travis-ci.org/iresty/apisix.svg?branch=master)](https://travis-ci.org/iresty/apisix)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/iresty/apisix/blob/master/LICENSE)
[![Coverage Status](https://coveralls.io/repos/github/iresty/apisix/badge.svg?branch=master)](https://coveralls.io/github/iresty/apisix?branch=master)

- **QQ group**: 552030619
- [![Gitter](https://badges.gitter.im/apisix/community.svg)](https://gitter.im/apisix/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)
- [![Twitter](https://img.shields.io/twitter/follow/apisixfast.svg?style=social&label=Follow)](https://twitter.com/intent/follow?screen_name=apisixfast)

## What's APISIX?

APISIX is a cloud-native microservices API gateway, delivering the ultimate performance, security, open source and scalable platform for all your APIs and microservices.

APISIX is based on OpenResty and etcd. Compared with traditional API gateways, APISIX has dynamic routing and plug-in hot loading, which is especially suitable for API management under micro-service system.


## Why APISIX?

If you are building a website, mobile device or IoT (Internet of Things) application, you may need to use an API gateway to handle interface traffic.

APISIX is a cloud-based microservices API gateway that handles traditional north-south traffic and handles east-west traffic between services.

APISIX provides dynamic load balancing, authentication, rate limiting, and other plugins through plugin mechanisms, and supports plugins you develop yourself.

For more detailed information, see the [White Paper](https://www.iresty.com/download/Choosing%20the%20Right%20Microservice%20API%20Gateway%20for%20the%20Enterprise%20User.pdf).

![](doc/images/apisix.png)

## Features

- **Cloud-Native**
- **Dynamic Load Balancing**
- **Hash-based Load Balancing**
- **SSL**
- **Monitoring**
- **Forward Proxy**
- **Authentications**
- **Limit-rate**
- **Limit-count**
- **Limit-concurrency**
- **CLI**
- **REST API**
- **Clustering**
- **Scalability**
- **High performance**
- **Custom plugins**
- **Anti-ReDoS(Regular expression Denial of Service)**
- **[Health Checks](doc/health-check.md)**.
- **Caching**: TODO.
- **Dashboard**: TODO.
- **OAuth2.0**: TODO.
- **ACL**: TODO.
- **Bot detection**: TODO.
- **IP blacklist**: TODO.

## Install

APISIX Installed and tested in the following systems:

| OS           | OpenResty | Status |
| ------------ | --------- | ------ |
| CentOS 7     | 1.15.8.1  | √      |
| Ubuntu 18.04 | 1.15.8.1  | √      |
| Debian 9     | 1.15.8.1  | √      |

You now have two ways to install APISIX: if you are using CentOS 7, it is recommended to use RPM, other systems please use Luarocks.

We will add support for Docker and more OS shortly.

### Install from RPM for CentOS 7

```shell
sudo yum install yum-utils
sudo yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo
sudo yum install -y openresty etcd
sudo service etcd start

sudo yum install -y https://github.com/iresty/apisix/releases/download/v0.5/apisix-0.5-0.el7.noarch.rpm
```

You can try APISIX with the [**Quickstart**](#quickstart) now.

### Install from Luarocks

#### Dependencies

APISIX is based on [OpenResty](https://openresty.org/), the configures data storage and distribution via [etcd](https://github.com/etcd-io/etcd).

We recommend that you use [luarocks](https://luarocks.org/) to install APISIX, and for different operating systems have different dependencies, see more: [Install Dependencies](doc/install-dependencies.md)

#### Install APISIX

```shell
sudo luarocks install --lua-dir=/usr/local/openresty/luajit apisix
```

If all goes well, you will see the message like this:

> apisix is now built and installed in /usr (license: Apache License 2.0)

Congratulations, you have already installed APISIX successfully.

## Development Manual of APISIX

If you are a developer, you can view the [dev manual](doc/dev-manual.md) for more detailed information.

## Quickstart

1. start server:

```shell
sudo apisix start
```

2. try limit count plugin

Limit count plugin is a good start to try APISIX,
you can follow the [documentation of limit count](doc/plugins/limit-count.md).


You can try more [plugins](doc/plugins.md).

## Benchmark

Using Google Cloud's 4 core server, APISIX's QPS reach to 60,000 with a latency of only 500 microseconds.

You can view the [benchmark documentation](doc/benchmark.md) for more detailed information.

## Architecture Design

English Development Documentation: TODO

[中文开发文档](doc/architecture-design-cn.md)

## Landscape

APISIX enriches the [CNCF API Gateway Landscape](https://landscape.cncf.io/category=api-gateway&format=card-mode&grouping=category):

![](doc/images/cncf-landscope.png)

## Contributing

Contributions are welcomed and greatly appreciated.

## Acknowledgments

inspired by Kong and Orange.
