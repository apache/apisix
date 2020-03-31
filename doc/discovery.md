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

# Integration service discovery registry

## Summary

When system traffic changes, the number of servers of the downstream service also increases or decreases, or the server needs to be replaced due to its hardware failure. If the gateway maintains downstream service information through configuration, the maintenance costs in the microservices architecture pattern are unpredictable. Furthermore, due to the untimely update of these information, will also bring a certain impact for the business, and the impact of human error operation can not be ignored. So it is very necessary for the gateway to automatically get the latest list of service instances through the service registry。As shown in the figure below：

![](./images/discovery.png)

1. When the service starts, it will report some of its information, such as the service name, IP, port and other information to the registry. The services communicate with the registry using a mechanism such as a heartbeat, and if the registry and the service are unable to communicate for a long time, the instance will be cancel.When the service goes offline, the registry will delete the instance information.
2. The gateway gets service instance information from the registry in near-real time.
3. When the user requests the service through the gateway, the gateway selects one instance from the registry for proxy.

Common registries: Eureka, Etcd, Consul, Zookeeper, Nacos etc.

## Enabled discovery client

Add the following configuration to `conf/config.yaml` file and select one discovery client type which you want:

```yaml
apisix:
  discovery: eureka
```

The supported discovery client: Eureka.

## Configuration for discovery client

Once the registry is selected, it needs to be configured.

### Configuration for Eureka

Add following configuration in `conf/config.yaml` ：

```yaml
eureka:
  host:                            # it's possible to define multiple eureka hosts addresses of the same eureka cluster.
    - "http://${usename}:${passowrd}@${eureka_host1}:${eureka_port1}"
    - "http://${usename}:${passowrd}@${eureka_host2}:${eureka_port2}"
  prefix: "/eureka/"
  weight: 100                      # default weight for node
  timeout:
    connect: 2000
    send: 2000
    read: 5000
```


**Tip**： It would be even better if these configurations could be moved to the configuration center for management.

## Upstream setting

Here is an example of routing a request with a uri of "/user/*" to a service which named "user-service"  in the registry :

```shell
$ curl http://127.0.0.1:9080/apisix/admin/routes/1 -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -i -d '
{
    "uri": "/user/*",
    "upstream": {
        "service_name": "USER-SERVICE",
        "type": "roundrobin"
    }
}'

HTTP/1.1 201 Created
Date: Sat, 31 Aug 2019 01:17:15 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive
Server: APISIX web server

{"node":{"value":{"uri":"\/user\/*","upstream": {"service_name": "USER-SERVICE", "type": "roundrobin"}},"createdIndex":61925,"key":"\/apisix\/routes\/1","modifiedIndex":61925},"action":"create"}
```

*Notice**：When configuring `upstream.service_name`,  `upstream.nodes` will no longer take effect, but will be replaced by 'nodes' obtained from the registry.

## How do I extend the discovery client?

It is very easy for APISIX to extend the discovery client. Let's take Eureka as an example.

### 1. the code structure of discovery client

First, add 'eureka.lua' in the 'lua/apisix/discovery/' directory;

Then implement the 'init_worker' function for initialization and the 'nodes' function for obtaining the list of service instance nodes in' eureka.lua':

  ```lua
  local _M = {
      version = 1.0,
  }


  function _M.nodes(service_name)
      ... ...
  end


  function _M.init_worker()
      ... ...
  end


  return _M
  ```

### 2. How convert Eureka's instance data to APISIX's node?

Here's an example of Eureka's data：

```json
{
  "applications": {
      "application": [
          {
              "name": "USER-SERVICE",                 # service name
              "instance": [
                  {
                      "instanceId": "192.168.1.100:8761",
                      "hostName": "192.168.1.100",
                      "app": "USER-SERVICE",          # service name
                      "ipAddr": "192.168.1.100",      # IP address
                      "status": "UP",
                      "overriddenStatus": "UNKNOWN",
                      "port": {
                          "$": 8761,
                          "@enabled": "true"
                      },
                      "securePort": {
                          "$": 443,
                          "@enabled": "false"
                      },
                      "metadata": {
                          "management.port": "8761",
                          "weight": 100               # Setting by 'eureka.instance.metadata-map.weight' of the spring boot application
                      },
                      "homePageUrl": "http://192.168.1.100:8761/",
                      "statusPageUrl": "http://192.168.1.100:8761/actuator/info",
                      "healthCheckUrl": "http://192.168.1.100:8761/actuator/health",
                      ... ...
                  }
              ]
          }
      ]
  }
}
```

Deal with the Eureka's instance data need the following steps :

1. select the UP instance. When the value of `overriddenStatus` is "UP" or the value of `overriddenStatus` is "UNKNOWN" and the value of `status` is "UP".
2. Host. The `ipAddr` is the IP address of instance; and must be IPv4 or IPv6.
3. Port. If the value of `port["@enabled"]` is equal to "true", using the value of `port["\$"]`, If the value of `securePort["@enabled"]` is equal to "true", using the value of `securePort["\$"]`.
4. Weight. `local weight =  metadata.weight or local_conf.eureka.weight or 100`

The result of this example is as follows:

```json
[
  {
    "host" : "192.168.1.100",
    "port" : 8761,
    "weight" : 100,
    "metadata" : {
      "management.port": "8761",
      "weight": 100
    }
  }
]
```
