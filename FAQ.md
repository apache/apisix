# FAQ

##  Why a new API gateway?

There are new requirements for API gateways in the field of microservices: higher flexibility, higher performance requirements, and cloud native.

##  What are the differences between APISIX and other API gateways?

APISIX is based on etcd to save and synchronize configuration, not relational databases such as Postgres or MySQL.

This not only eliminates polling, makes the code more concise, but also makes configuration synchronization more real-time. At the same time, there will be no single point in the system, which is more usable.

In addition, APISIX has dynamic routing and hot loading of plug-ins, which is especially suitable for API management under micro-service system.

## What's the performance of APISIX?

One of the goals of APISIX design and development is the highest performance in the industry. Specific test data can be found here：[benchmark](https://github.com/iresty/apisix/blob/master/doc/benchmark.md)

APISIX is the highest performance API gateway with a single-core QPS of 23,000, with an average delay of only 0.6 milliseconds.

## Does APISIX have a console interface?

Yes, in version 0.6 we have dashboard built in, you can operate APISIX through the web interface.

## Can I write my own plugin?

Of course, APISIX provides flexible custom plugins for developers and businesses to write their own logic.

## Why we choose etcd as the configuration center?

For the configuration center, configuration storage is only the most basic function, and APISIX also needs the following features:

1. Cluster
2. Transactions
3. Multi-version Concurrency Control
4. Change Notification
5. High Performance

See more [etcd why](https://github.com/etcd-io/etcd/blob/master/Documentation/learning/why.md#comparison-chart).
