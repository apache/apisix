<!--
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
-->

# FAQ

##  Why a new API gateway?

There are new requirements for API gateways in the field of microservices: higher flexibility, higher performance requirements, and cloud native.

##  What are the differences between APISIX and other API gateways?

APISIX is based on etcd to save and synchronize configuration, not relational databases such as Postgres or MySQL.

This not only eliminates polling, makes the code more concise, but also makes configuration synchronization more real-time. At the same time, there will be no single point in the system, which is more usable.

In addition, APISIX has dynamic routing and hot loading of plug-ins, which is especially suitable for API management under micro-service system.

## What's the performance of APISIX?

One of the goals of APISIX design and development is the highest performance in the industry. Specific test data can be found here：[benchmark](https://github.com/apache/incubator-apisix/blob/master/doc/benchmark.md)

APISIX is the highest performance API gateway with a single-core QPS of 23,000, with an average delay of only 0.6 milliseconds.

## Does APISIX have a console interface?

Yes, in version 0.6 we have dashboard built in, you can operate APISIX through the web interface.

## Can I write my own plugin?

Of course, APISIX provides flexible custom plugins for developers and businesses to write their own logic.

[How to write plugin](doc/plugins/plugin-develop.md)

## Why we choose etcd as the configuration center?

For the configuration center, configuration storage is only the most basic function, and APISIX also needs the following features:

1. Cluster
2. Transactions
3. Multi-version Concurrency Control
4. Change Notification
5. High Performance

See more [etcd why](https://github.com/etcd-io/etcd/blob/master/Documentation/learning/why.md#comparison-chart).

## Why is it that installing APISIX dependencies with Luarocks causes timeout, slow or unsuccessful installation?

There are two possibilities when encountering slow luarocks:

1. Server used for luarocks installation is blocked
2. There is a place between your network and github server to block the 'git' protocol

For the first problem, you can use https_proxy or use the `--server` option to specify a luarocks server that you can access or access faster.
Run the `luarocks config rocks_servers` command(this command is supported after luarocks 3.0) to see which server are available.

If using a proxy doesn't solve this problem, you can add `--verbose` option during installation to see exactly how slow it is. Excluding the first case, only the second that the `git` protocol is blocked. Then we can run `git config --global url."https://".insteadOf git://` to using the 'HTTPS' protocol instead of `git`.
