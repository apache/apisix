[English](plugins.md)
## 插件
目前已支持这些插件：

* [HTTPS](https.md)：根据 TLS 扩展字段 SNI(Server Name Indication) 动态加载证书。
* [动态负载均衡](architecture-design-cn.md#upstream)：跨多个上游服务的动态负载均衡，目前已支持 round-robin 和一致性哈希算法。
* [key-auth](plugins/key-auth-cn.md)：基于 Key Authentication 的用户认证。
* [JWT-auth](plugins/jwt-auth-cn.md)：基于 [JWT](https://jwt.io/) (JSON Web Tokens) Authentication 的用户认证。
* [limit-count](plugins/limit-count-cn.md)：基于“固定窗口”的限速实现。
* [limit-req](plugins/limit-req-cn.md)：基于漏桶原理的请求限速实现。
* [limit-conn](plugins/limit-conn-cn.md)：限制并发请求（或并发连接）。
* [prometheus](plugins/prometheus.md)：以 Prometheus 格式导出 APISIX 自身的状态信息，方便被外部 Prometheus 服务抓取。
* [OpenTracing](plugins/zipkin.md)：支持 Zikpin 和 Apache SkyWalking。
* [grpc-transcode](plugins/grpc-transcoding-cn.md)：REST <--> gRPC 转码。
* [serverless](plugins/serverless-cn.md)：允许在 APISIX 中的不同阶段动态运行 Lua 代码。
* [ip-restriction](plugins/ip-restriction.md): IP 黑白名单。
* openid-connect
