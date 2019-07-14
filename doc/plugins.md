[中文](plugins-cn.md)
## Plugins
Now we support the following plugins:
* [HTTPS](https.md): dynamic load the SSL Certificate by Server Name Indication (SNI).
* [dynamic load balancing](#Plugins): load balance traffic across multiple upstream services, supports round-robin and consistent hash algorithms.
* [key-auth](plugins/key-auth.md): user authentication based on Key Authentication.
* [limit-count](plugins/limit-count.md): rate limiting based on a "fixed window" implementation.
* [limit-req](plugins/limit-req.md): request rate limiting and adjustment based on the "leaky bucket" method.
* [limit-conn](plugins/limit-conn.md): limite request concurrency (or concurrent connections).
* [prometheus](plugins/prometheus.md): expose metrics related to APISIX and proxied upstream services in Prometheus exposition format, which can be scraped by a Prometheus Server.
