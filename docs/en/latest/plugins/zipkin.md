---
title: Zipkin
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

## Summary

- [**Name**](#name)
- [**Attributes**](#attributes)
- [**How To Enable**](#how-to-enable)
- [**Test Plugin**](#test-plugin)
- [**Disable Plugin**](#disable-plugin)

## Name

[Zipkin](https://github.com/openzipkin/zipkin) is a OpenTracing plugin.

It's also works with `Apache SkyWalking`, which is support Zipkin v1/v2 format.

## Attributes

| Name         | Type   | Requirement | Default  | Valid        | Description                                                                     |
| ------------ | ------ | ----------- | -------- | ------------ | ------------------------------------------------------------------------------- |
| endpoint     | string | required    |          |              | the http endpoint of Ziplin, for example: `http://127.0.0.1:9411/api/v2/spans`. |
| sample_ratio | number | required    |          | [0.00001, 1] | the ratio of sample                                                             |
| service_name | string | optional    | "APISIX" |              | service name for zipkin reporter                                                |
| server_addr  | string | optional    |          |              | IPv4 address for zipkin reporter, default is nginx built-in variables $server_addr, here you can specify your external ip address. |
| span_version | integer| optional    | 2        | [1, 2]       | the version of span type |

Currently each traced request will create spans below:

```
request
├── proxy: from the beginning of the request to the beginning of header filter
└── response: from the beginning of header filter to the beginning of log
```

Previously we created spans below:

```
request
├── rewrite
├── access
└── proxy
    └── body_filter
```

Note: the name of span doesn't represent the corresponding Nginx's phase.

If you need to be compatible with old style, we can set `span_version` to 1.

## How To Enable

Here's an example, enable the zipkin plugin on the specified route:

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
            "39.97.63.215:80": 1
        }
    }
}'
```

You can open dashboard with a browser: `http://127.0.0.1:9080/apisix/dashboard/`, to complete the above operation through the web interface, first add a route:

![](../../../assets/images/plugin/zipkin-1.png)

Then add zipkin plugin:

![](../../../assets/images/plugin/zipkin-2.png)

## Test Plugin

### run the Zipkin instance

e.g. using docker:

```
sudo docker run -d -p 9411:9411 openzipkin/zipkin
```

Here is a test example:

```shell
$ curl http://127.0.0.1:9080/index.html
HTTP/1.1 200 OK
...
```

Then you can use a browser to access the webUI of Zipkin:

```
http://127.0.0.1:9411/zipkin
```

![](../../../assets/images/plugin/zipkin-1.jpg)

![](../../../assets/images/plugin/zipkin-2.jpg)

## Disable Plugin

When you want to disable the zipkin plugin, it is very simple,
 you can delete the corresponding json configuration in the plugin configuration,
  no need to restart the service, it will take effect immediately:

```shell
$ curl http://127.0.0.1:2379/v2/keys/apisix/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d value='
{
    "methods": ["GET"],
    "uri": "/index.html",
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "39.97.63.215:80": 1
        }
    }
}'
```

The zipkin plugin has been disabled now. It works for other plugins.

## example code for upstream ( golang with Gin )

```golang
func GetTracer(serviceName string, port int, enpoitUrl string, rate float64) *zipkin.Tracer {
    // create a reporter to be used by the tracer
    reporter := httpreporter.NewReporter(enpoitUrl)
    // set-up the local endpoint for our service host is ip:host

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
