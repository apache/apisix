---
title: skywalking
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
- [**How to set endpoint**](#how-to-set-endpoint)
- [**Test Plugin**](#test-plugin)
  - [**Run SkyWalking Example**](#run-skywalking-example)
- [**Disable Plugin**](#disable-plugin)
- [**Upstream services(Code With SpringBoot)**](#Upstream-services(Code-With-SpringBoot))

## Name

[**SkyWalking**](https://github.com/apache/skywalking) uses its native Nginx LUA tracer to provide tracing, topology analysis, and metrics from service and URI perspective.

The SkyWalking server can support both HTTP and gRPC protocols. Currently, the APISIX client only supports the HTTP protocol.

## Attributes

| Name         | Type   | Requirement | Default  | Valid        | Description                                                          |
| ------------ | ------ | ----------- | -------- | ------------ | -------------------------------------------------------------------- |
| sample_ratio | number | required    | 1        | [0.00001, 1] | the ratio of sampling                                               |

## How To Enable

First of all, enable the SkyWalking plugin in the `config.yaml`:

```
# Add this in config.yaml
plugins:
  - ... # plugin you need
  - skywalking
```

Then reload APISIX, a background timer will be created to report data to the SkyWalking OAP server.

Here's an example, enable the SkyWalking plugin on the specified route:

```shell
curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uris": [
        "/uid/*"
    ],
    "plugins": {
        "skywalking": {
            "sample_ratio": 1
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "10.110.149.175:8089": 1
        }
    }
}'
```

You also can complete the above operation through the web interface, first add a route, then add SkyWalking plugin:

![ ](../../../assets/images/plugin/skywalking-1.png)

## How to set endpoint

We can set the endpoint by specifying the configuration in `conf/config.yaml`.

| Name         | Type   | Default  | Description                                                          |
| ------------ | ------ | -------- | -------------------------------------------------------------------- |
| service_name | string | "APISIX" | service name for SkyWalking reporter                                 |
| service_instance_name | string |"APISIX Instance Name" | service instance name for SkyWalking reporter，  set it to `$hostname` to get local hostname directly.|
| endpoint_addr | string | "http://127.0.0.1:12800" | the HTTP endpoint of SkyWalking, for example: http://127.0.0.1:12800 |
| report_interval | integer | use the value in the SkyWalking client library | the report interval, in seconds |

Here is an example:

```yaml
plugin_attr:
  skywalking:
    service_name: APISIX
    service_instance_name: "APISIX Instance Name"
    endpoint_addr: http://127.0.0.1:12800
```

## Test Plugin

### Run SkyWalking Example

1. Start the SkyWalking OAP Server:
    - By default, SkyWalking uses H2 storage, start SkyWalking directly by

        ```shell
        sudo docker run --name skywalking -d -p 1234:1234 -p 11800:11800 -p 12800:12800 --restart always apache/skywalking-oap-server:8.7.0-es6
        ```

    - Of Course, you may want to use Elasticsearch storage instead

        1. First, you should install Elasticsearch:

            ```shell
            sudo docker run -d --name elasticsearch -p 9200:9200 -p 9300:9300 --restart always -e "discovery.type=single-node" elasticsearch:6.7.2
            ```

        2. Optionally, you can install ElasticSearch management page: elasticsearch-hq

            ```shell
            sudo docker run -d --name elastic-hq -p 5000:5000 --restart always elastichq/elasticsearch-hq
            ```

        3. Finally, run SkyWalking OAP server:

            ```shell
            sudo docker run --name skywalking -d -p 1234:1234 -p 11800:11800 -p 12800:12800 --restart always --link elasticsearch:elasticsearch -e SW_STORAGE=elasticsearch -e SW_STORAGE_ES_CLUSTER_NODES=elasticsearch:9200 apache/skywalking-oap-server:8.7.0-es6
            ```

2. SkyWalking Web UI:
    1. Run SkyWalking web UI Server:

        ```shell
        sudo docker run --name skywalking-ui -d -p 8080:8080 --link skywalking:skywalking -e SW_OAP_ADDRESS=skywalking:12800 --restart always apache/skywalking-ui
        ```

    2. Access the web UI of SkyWalking:
        You can access the dashboard from a browser: http://10.110.149.175:8080 It will show the following
        if the installation is successful.
        ![ ](../../../assets/images/plugin/skywalking-3.png)

3. Test:

    - Access to upstream services through accessing APISIX:

        ```bash
        $ curl -v http://10.110.149.192:9080/uid/12
        HTTP/1.1 200 OK
        OK
        ...
        ```

    - Open the web UI of SkyWalking:

        ```shell
        http://10.110.149.175:8080/
        ```

        You can see the topology of all services\
        ![ ](../../../assets/images/plugin/skywalking-4.png)\
        You can also see the traces from all services\
        ![ ](../../../assets/images/plugin/skywalking-5.png)

## Disable Plugin

When you want to disable the SkyWalking plugin on a route/service, it is very simple,
 you can delete the corresponding JSON configuration in the plugin configuration,
  no need to restart the service, it will take effect immediately:

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1  -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uris": [
        "/uid/*"
    ],
    "plugins": {
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "10.110.149.175:8089": 1
        }
    }
}'
```

The SkyWalking plugin has been disabled now. The step works in the same fashion for other plugins.

If you want to completely disable the SkyWalking plugin, for example, stopping the background report timer,
you will need to comment out the plugin in the `config.yaml`:

```yaml
plugins:
  - ... # plugin you need
  #- skywalking
```

And then reload APISIX.

## Upstream services(Code With SpringBoot)

```java
package com.lenovo.ai.controller;

import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import javax.servlet.http.HttpServletRequest;

/**
 * @author cyxinda
 * @create 2020-05-29 14:02
 * @desc skywalking test controller
 **/
@RestController
public class TestController {
    @RequestMapping("/uid/{count}")
    public String getUidList(@PathVariable("count") String countStr, HttpServletRequest request) {
        System.out.println("counter:::::-----"+countStr);
       return "OK";
    }
}
```

Configure the SkyWalking agent when starting the service.

Update the file of `agent/config/agent.config`

```shell
agent.service_name=yourservername
collector.backend_service=10.110.149.175:11800
```

Run the script:

```shell
nohup java -javaagent:/root/skywalking/app/agent/skywalking-agent.jar \
-jar /root/skywalking/app/app.jar \
--server.port=8089 \
2>&1 > /root/skywalking/app/logs/nohup.log &
```
