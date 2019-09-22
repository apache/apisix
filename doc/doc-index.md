
[中文](doc-index.md)

* [Architecture Design](architecture-design-cn.md)
* [Benchmark](benchmark.md)
* [Build development ENV](dev-manual.md)
* [Install Dependencies](install-dependencies.md): How to install dependencies for different OS.
* [Health Check](health-check.md): Enable health check on the upstream node, and will automatically filter unhealthy nodes during load balancing to ensure system stability.
* [Plugins](plugins.md)
    * [HTTPS](https.md): dynamic load the SSL Certificate by Server Name Indication (SNI).
    * [dynamic load balancing](#Plugins): load balance traffic across multiple upstream services, supports round-robin and consistent hash algorithms.
    * [key-auth](plugins/key-auth.md): user authentication based on Key Authentication.
    * [JWT-auth](plugins/jwt-auth-cn.md): user authentication based on [JWT](https://jwt.io/) (JSON Web Tokens) Authentication.
    * [limit-count](plugins/limit-count.md): rate limiting based on a "fixed window" implementation.
    * [limit-req](plugins/limit-req.md): request rate limiting and adjustment based on the "leaky bucket" method.
    * [limit-conn](plugins/limit-conn.md): limite request concurrency (or concurrent connections).
    * [prometheus](plugins/prometheus.md): expose metrics related to APISIX and proxied upstream services in Prometheus exposition format, which can be scraped by a Prometheus Server.
    * [OpenTracing](plugins/zipkin.md): support Zikpin and Apache SkyWalking.
    * [grpc-transcode](plugins/grpc-transcode-cn.md): REST <--> gRPC transcoding。
    * [serverless](plugins/serverless-cn.md)：allow to dynamically run Lua code at *different* phase in APISIX.
    * [ip-restriction](plugins/ip-restriction.md): IP whitelist/blacklist.
    * openid-connect
* Router
    * [radixtree](router-radixtree.md)
    * [r3](router-r3.md)
* [Stand Alone Model](stand-alone.md)
* [stream-proxy](stream-proxy.md)
