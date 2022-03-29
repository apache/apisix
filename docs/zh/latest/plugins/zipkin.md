---
title: zipkin
---

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

## 描述

[Zipkin](https://github.com/openzipkin/zipkin) 是一个开源的分布调用链追踪系统。该插件基于[Zipkin API 规范](https://zipkin.io/pages/instrumenting.html)，支持收集跟踪信息，并上报 Zipkin Collector。

> 它还能够与适配了 Zipkin [v1](https://zipkin.io/zipkin-api/zipkin-api.yaml)/[v2](https://zipkin.io/zipkin-api/zipkin2-api.yaml) 的 [Apache SkyWalking](https://skywalking.apache.org/docs/main/latest/en/setup/backend/zipkin-trace/#zipkin-receiver) 和 [Jaeger](https://www.jaegertracing.io/docs/1.31/getting-started/#migrating-from-zipkin)。当然，它也能够与其它支持 Zipkin v1/v2 数据格式的调用链追踪系统集成。

## 属性

| 名称         | 类型   | 必选项 | 默认值   | 有效值       | 描述                                                                 |
| ------------ | ------ | ------ | -------- | ------------ | -------------------------------------------------------------------- |
| endpoint     | string | 必须   |          |              | Zipkin 的 http 节点，例如`http://127.0.0.1:9411/api/v2/spans`。      |
| sample_ratio | number | 必须   |          | [0.00001, 1] | 监听的比例                                                           |
| service_name | string | 可选   | "APISIX" |              | 标记当前服务的名称                                                   |
| server_addr  | string | 可选   |          |              | 标记当前 APISIX 实例的 IP 地址，默认值是 nginx 的内置变量`server_addr` |
| span_version | integer| 可选    | 2        | [1, 2]       | span 类型版本 |

目前每个被跟踪的请求会创建下面的 span：

```
request
├── proxy: from the beginning of the request to the beginning of header filter
└── response: from the beginning of header filter to the beginning of log
```

之前我们创建的 span 是这样：

```
request
├── rewrite
├── access
└── proxy
    └── body_filter
```

注意上述的 span 的名称跟同名的 Nginx phase 没有关系。

如果你需要兼容过去的 span 类型，可以把 `span_version` 设置成 1。

## 如何启用

下面是一个示例，在指定的 route 上开启了 zipkin 插件：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
        "zipkin": {
            "endpoint": "http://127.0.0.1:9411/api/v2/spans",
            "sample_ratio": 1,
            "service_name": "APISIX-IN-SG",
            "server_addr": "192.168.3.50"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

你也可以通过 web 界面来完成上面的操作，先增加一个 route，然后在插件页面中添加 zipkin 插件：

![enable zipkin plugin](../../../assets/images/plugin/zipkin-1.png)

## 测试插件

### 运行 Zipkin 实例

e.g. 用 docker:

```
docker run -d -p 9411:9411 openzipkin/zipkin
```

测试示例：

```shell
curl http://127.0.0.1:9080/index.html
HTTP/1.1 200 OK
...
```

在浏览器访问`http://127.0.0.1:9411/zipkin`，在 Zipkin WebUI 上查询 traces：

![zipkin web-ui](../../../assets/images/plugin/zipkin-1.jpg)

![zipkin web-ui list view](../../../assets/images/plugin/zipkin-2.jpg)

### Run the Jaeger instance

除了对接 Zipkin，该插件也支持将 traces 上报到 Jaeger。下面运行在`docker`环境上的示例：
首先，运行 Jaeger 后端服务：

```
docker run -d --name jaeger \
  -e COLLECTOR_ZIPKIN_HOST_PORT=:9411 \
  -p 16686:16686 \
  -p 9411:9411 \
  jaegertracing/all-in-one:1.31
```

创建路由，并且配置 Zipkin：

```
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
        "zipkin": {
            "endpoint": "http://127.0.0.1:9411/api/v2/spans",
            "sample_ratio": 1,
            "service_name": "APISIX-IN-SG",
            "server_addr": "192.168.3.50"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

访问服务：

```shell
curl http://127.0.0.1:9080/index.html
HTTP/1.1 200 OK
...
```

然后在浏览器中打开`http://127.0.0.1:16686`，在 Jaeger WebUI 上查询 traces：

![jaeger web-ui](../../../assets/images/plugin/jaeger-1.png)

![jaeger web-ui trace](../../../assets/images/plugin/jaeger-2.png)

## 禁用插件

当你想去掉插件的时候，很简单，在插件的配置中把对应的 json 配置删除即可，无须重启服务，即刻生效：

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "127.0.0.1:1980": 1
        }
    }
}'
```

现在就已经移除了 Zipkin 插件了。其他插件的开启和移除也是同样的方法。

## 上游服务是 Golang 的示例代码

```golang
func GetTracer(serviceName string, port int, enpoitUrl string, rate float64) *zipkin.Tracer {
    // create a reporter to be used by the tracer
    reporter := httpreporter.NewReporter(enpoitUrl)
    // set-up the local endpoint for our service host is  ip:host

    thisip, _ := GetLocalIP()

    host := fmt.Sprintf("%s:%d", thisip, port)
    endpoint, _ := zipkin.NewEndpoint(serviceName, host)
    // set-up our sampling strategy
    sampler, _ := zipkin.NewCountingSampler(rate)
    // initialize the tracer
    tracer, _ := zipkin.NewTracer(
        reporter,
        zipkin.WithLocalEndpoint(endpoint),
        zipkin.WithSampler(sampler),
    )
    return tracer
}

func main(){
    r := gin.Default()

    tracer := GetTracer(...)

    // use middleware to extract parentID from http header that injected by APISIX
    r.Use(func(c *gin.Context) {
        span := this.Tracer.Extract(b3.ExtractHTTP(c.Request))
        childSpan := this.Tracer.StartSpan(spanName, zipkin.Parent(span))
        defer childSpan.Finish()
        c.Next()
    })

}
```
