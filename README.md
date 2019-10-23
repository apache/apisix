[中文](README_CN.md)
## APISIX

[![Build Status](https://travis-ci.org/iresty/apisix.svg?branch=master)](https://travis-ci.org/iresty/apisix)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/iresty/apisix/blob/master/LICENSE)

- **QQ group**: 552030619
- [![Gitter](https://badges.gitter.im/apisix/community.svg)](https://gitter.im/apisix/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)
- [![Twitter](https://img.shields.io/twitter/follow/apisixfast.svg?style=social&label=Follow)](https://twitter.com/intent/follow?screen_name=apisixfast)

APISIX is a cloud-native microservices API gateway, delivering the ultimate performance, security, open source and scalable platform for all your APIs and microservices.

APISIX is based on OpenResty and etcd. Compared with traditional API gateways, APISIX has dynamic routing and plug-in hot loading, which is especially suitable for API management under micro-service system.

[Installation](#Installation) | [Documentation](doc/README.md) | [Development ENV](#development-manual-of-apisix) | [FAQ](FAQ.md)

## Why APISIX?

If you are building a website, mobile device or IoT (Internet of Things) application, you may need to use an API gateway to handle interface traffic.

APISIX is a cloud-based microservices API gateway that handles traditional north-south traffic and handles east-west traffic between services.

APISIX provides dynamic load balancing, authentication, rate limiting, and other plugins through plugin mechanisms, and supports plugins you develop yourself.

For more detailed information, see the [White Paper](https://www.iresty.com/download/Choosing%20the%20Right%20Microservice%20API%20Gateway%20for%20the%20Enterprise%20User.pdf).

![](doc/images/apisix.png)

## Features

- **Cloud-Native**: Platform agnostic, No vendor lock-in, APISIX can run from bare-metal to Kubernetes.
- **[Hot Updates And Hot Plugins](doc/plugins.md)**: Continuously updates its configurations and plugins without restarts!
- **Dynamic Load Balancing**: Round-robin load balancing with weight.
- **Hash-based Load Balancing**: Load balance with consistent hashing sessions.
- **[SSL](doc/https.md)**: Dynamically load an SSL certificate.
- **HTTP(S) Forward Proxy**
- **[Health Checks](doc/health-check.md)**：Enable health check on the upstream node, and will automatically filter unhealthy nodes during load balancing to ensure system stability.
- **Circuit-Breaker**: Intelligent tracking of unhealthy upstream services.
- **Authentications**: [key-auth](doc/plugins/key-auth.md), [JWT](doc/plugins/jwt-auth.md)
- **[Limit-req](doc/plugins/limit-req.md)**
- **[Limit-count](doc/plugins/limit-count.md)**
- **[Limit-concurrency](doc/plugins/limit-conn.md)**
- **[Proxy Rewrite](doc/plugins/proxy-rewrite.md)**: Support for rewriting the `host`, `uri`, `schema`, `enable_websocket`, `headers` information upstream of the request.
- **OpenTracing: [support Apache Skywalking and Zipkin](doc/plugins/zipkin.md)**
- **Monitoring And Metrics**: [Prometheus](doc/plugins/prometheus.md)
- **[gRPC transcoding](doc/plugins/grpc-transcoding.md)**：Supports protocol transcoding so that clients can access your gRPC API by using HTTP/JSON.
- **[Serverless](doc/plugins/serverless.md)**: Invoke functions in each phase in APISIX.
- **Custom plugins**: Allows hooking of common phases, such as `rewrite`, `access`, `header filer`, `body filter` and `log`, also allows to hook the `balancer` stage.
- **Dashboard**: Built-in dashboard to control APISIX.
- **Version Control**: Supports rollbacks of operations.
- **CLI**: start\stop\reload APISIX through the command line.
- **REST API**
- **Proxy Websocket**
- **IPv6**: Use IPv6 to match route.
- **Clustering**: APISIX nodes are stateless, creates clustering of the configuration center, please refer to [etcd Clustering Guide](https://github.com/etcd-io/etcd/blob/master/Documentation/v2/clustering.md).
- **Scalability**: plug-in mechanism is easy to extend.
- **High performance**: The single-core QPS reaches 24k with an average delay of less than 0.6 milliseconds.
- **Anti-ReDoS(Regular expression Denial of Service)**
- **IP Whitelist/Blacklist**
- **IdP**: Support external authentication services, such as Auth0, okta, etc., users can use this to connect to Oauth2.0 and other authentication methods.
- **[Stand-alone mode](doc/stand-alone.md)**: Supports to load route rules from local yaml file, it is more friendly such as under the kubernetes(k8s).
- **Global Rule**: Allows to run any plugin for all request, eg: limit rate, IP filter etc.
- **[TCP/UDP Proxy](doc/stream-proxy.md)**: Dynamic TCP/UDP proxy.
- **[Dynamic MQTT Proxy](doc/plugins/mqtt-proxy.md)**: Supports to load balance MQTT by `client_id`, both support MQTT [3.1.*](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html), [5.0](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html).
- **ACL**: TODO.
- **Bot detection**: TODO.

## Online Demo Dashboard
We provide an online dashboard [demo version](http://apisix.iresty.com)， make it easier for you to understand APISIX.

## Installation

APISIX Installed and tested in the following systems, and the version of OpenResty MUST >= 1.15.8.1:

- CentOS 7
- Ubuntu 16.04
- Ubuntu 18.04
- Debian 9
- Debian 10
- macOS
- **ARM64** Ubuntu 18.04

You now have four ways to install APISIX:
- if you are using CentOS 7, it is recommended to use [RPM](#install-from-rpm-for-centos-7);
- if using macOS, only support git clone and install by manual, please take a look at [dev manual](doc/dev-manual.md);
- other systems please use [Luarocks](#install-from-luarocks-not-support-macos);
- You can also install from [Docker image](https://github.com/iresty/docker-apisix).

*NOTE*: APISIX currently only supports the v2 protocol storage to etcd, but the latest version of etcd (starting with 3.4) has turned off the v2 protocol by default. You need to add `--enable-v2=true` to the startup parameter to enable the v2 protocol. The development of the v3 protocol supporting etcd has begun and will soon be available.

### Install from RPM for CentOS 7

```shell
sudo yum install yum-utils
sudo yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo
sudo yum install -y openresty etcd
sudo service etcd start

sudo yum install -y https://github.com/iresty/apisix/releases/download/v0.8/apisix-0.8-0.el7.noarch.rpm
```

You can try APISIX with the [**Quickstart**](#quickstart) now.

### Install from Luarocks (not support macOS)

##### Dependencies

APISIX is based on [OpenResty](https://openresty.org/), the configures data storage and distribution via [etcd](https://github.com/etcd-io/etcd).

We recommend that you use [luarocks](https://luarocks.org/) to install APISIX, and for different operating systems have different dependencies, see more: [Install Dependencies](doc/install-dependencies.md)

##### Install APISIX

APISIX is installed by running the following commands in your terminal.

> Gets the master branch via curl

```shell
sudo sh -c "$(curl -fsSL https://raw.githubusercontent.com/iresty/apisix/master/utils/install-apisix.sh)"
```

> Gets the master branch with manual inspection

It's a good idea to inspect the installation script from projects you don't know yet. You can do that by downloading the installation script first, looking through it so everything looks normal, then running it:

```shell
curl -Lo install.sh https://raw.githubusercontent.com/iresty/apisix/master/utils/install-apisix.sh
sudo sh install.sh
```

> Gets the specified version via Luarock: 

```shell
# install apisix with version v0.8
sudo luarocks install --lua-dir=/path/openresty/luajit apisix 0.8

# old luarocks may not support `lua-dir`, we can remove option `lua-dir`
sudo luarocks install apisix 0.8
```

> Installation complete

If all goes well, you will see the message like this:

```
    apisix 0.7-0 is now built and installed in /usr/local/apisix/deps (license: Apache License 2.0)

    + sudo rm -f /usr/local/bin/apisix
    + sudo ln -s /usr/local/apisix/deps/bin/apisix /usr/local/bin/apisix
```

Congratulations, you have already installed APISIX successfully.

## Development Manual of APISIX

If you are a developer, you can view the [dev manual](doc/dev-manual.md) for more details.

## Quickstart

1. start server:

```shell
sudo apisix start
```

*note*: If you are in a development environment, start server by command `make run`.

2. try limit count plugin

Limit count plugin is a good start to try APISIX,
you can follow the [documentation of limit count](doc/plugins/limit-count.md).

Then you can try more [plugins](doc/README.md#plugins).

## Dashboard

APISIX has the built-in dashboard，open `http://127.0.0.1:9080/apisix/dashboard/` with a browser and try it.

Do not need to fill the user name and password, log in directly.

Dashboard allow any remote IP by default, and you can modify `allow_admin` in `conf/config.yaml` by yourself, to list the list of IPs allowed to access.

## Benchmark

Using Google Cloud's 4 core server, APISIX's QPS reach to 60,000 with a latency of only 500 microseconds.

You can view the [benchmark documentation](doc/benchmark.md) for more detailed information.

## Architecture Design

[Development Documentation](doc/architecture-design.md)

## Videos and slides

- [APISIX technology selection, testing and continuous integration(Chinese)](https://www.upyun.com/opentalk/432.html)

- [APISIX high performance practice(Chinese)](https://www.upyun.com/opentalk/429.html)

## Who Uses APISIX?
A wide variety of companies and organizations use APISIX for research, production and commercial product.
Here is the User Wall of APISIX.

![](doc/images/user-wall.jpg)

Users are encouraged to add themselves to the [Powered By](doc/powered-by.md) page.

## Landscape

APISIX enriches the [CNCF API Gateway Landscape](https://landscape.cncf.io/category=api-gateway&format=card-mode&grouping=category):

![](doc/images/cncf-landscope.jpg)

## FAQ

There are often some questions asked by developers in the community. We have arranged them in the [FAQ](FAQ.md).

If your concerns are not among them, please submit issue to communicate with us.

## Contributing

See [CONTRIBUTING](Contributing.md) for details on submitting patches and the contribution workflow.

## Acknowledgments

inspired by Kong and Orange.
