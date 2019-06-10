## APISIX

[![Build Status](https://travis-ci.org/iresty/apisix.svg?branch=master)](https://travis-ci.org/iresty/apisix)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/iresty/apisix/blob/master/LICENSE)

- **QQ group**: 552030619

## What's APISIX?

APISIX is a cloud-native microservices API gateway, delivering the ultimate performance, security, open source and scalable platform for all your APIs and microservices.

[中文简介](README_CN.md)

## Install

APISIX Installed and tested in the following systems:

|OS          |  OpenResty|Status|
|------------|-----------|------|
|CentOS 7    |   1.15.8.1|√     |
|Ubuntu 18.04|   1.15.8.1|√     |
|Debian 9    |   1.15.8.1|√     |

You now have two ways to install APISIX: if you are using CentOS 7, it is recommended to use RPM, other systems please use Luarocks.

We will add support for Docker and more OS shortly.

### Install from RPM for CentOS 7

```shell
sudo yum install yum-utils
sudo yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo
sudo yum install -y openresty etcd
sudo service etcd start

sudo yum install -y https://github.com/iresty/apisix/releases/download/v0.4/apisix-0.4-0.el7.noarch.rpm
```

You can try APISIX with the [**Quickstart**](#quickstart) now.

### Install from Luarocks

#### Dependencies

APISIX is based on [OpenResty](https://openresty.org/), the configures data storage and distribution via [etcd](https://github.com/etcd-io/etcd).

We recommend that you use [luarocks](https://luarocks.org/) to install APISIX, and for different operating systems have different dependencies, see more: [Install Dependencies](https://github.com/iresty/apisix/wiki/Install-Dependencies)

#### Install APISIX

```shell
sudo luarocks install apisix
```

If all goes well, you will see the message like this:
> apisix is now built and installed in /usr (license: Apache License 2.0)

Congratulations, you have already installed APISIX successfully.

## Quickstart

1. start server:
```shell
sudo apisix start
```

2. try limit count plugin

For the convenience of testing, we set up a maximum of 2 visits in 60 seconds,
and return 503 if the threshold is exceeded:

```shell
curl http://127.0.0.1:2379/v2/keys/apisix/routes/1 -X PUT -d value='
{
	"methods": ["GET"],
	"uri": "/index.html",
	"id": 1,
	"plugin_config": {
		"limit-count": {
			"count": 2,
			"time_window": 60,
			"rejected_code": 503,
			"key": "remote_addr"
		}
	},
	"upstream": {
		"type": "roundrobin",
		"nodes": {
			"39.97.63.215:80": 1
		}
	}
}'
```

```shell
$ curl -i http://127.0.0.1:9080/index.html
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 13175
Connection: keep-alive
X-RateLimit-Limit: 2
X-RateLimit-Remaining: 1
Server: APISIX web server
Date: Mon, 03 Jun 2019 09:38:32 GMT
Last-Modified: Wed, 24 Apr 2019 00:14:17 GMT
ETag: "5cbfaa59-3377"
Accept-Ranges: bytes

...
```

## Benchmark
Using Google Cloud's 4 core server, APISIX's QPS reach to 60,000 with a latency of only 500 microseconds.

You can view the [benchmark documentation](doc/benchmark.md) for more detailed information.

## Documentation
English Development Documentation: TODO

[中文开发文档](doc/architecture-design-cn.md)

## Plugins
Now we support the following plugins:
* [dynamic load balancing]: Load balance traffic across multiple upstream services.
* [key-auth](lua/apisix/plugins/key-auth.md): user authentication based on Key Authentication.
* [limit-count](lua/apisix/plugins/limit-count.md): rate limiting based on a "fixed window" implementation.
* [limit-req](lua/apisix/plugins/limit-req.md): request rate limiting and adjustment based on the "leaky bucket" method.
* [prometheus](lua/apisix/plugins/prometheus.md): expose metrics related to APISIX and proxied upstream services in Prometheus exposition format, which can be scraped by a Prometheus Server.

## Contributing
Contributions are welcomed and greatly appreciated.

## Acknowledgments
inspired by Kong
