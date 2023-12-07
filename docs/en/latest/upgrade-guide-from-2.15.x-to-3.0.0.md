---
title: Upgrade Guide
keywords:
  - APISIX
  - APISIX Upgrade Guide
  - APISIX Version Upgrade
description: Guide for upgrading APISIX from version 2.15.x to 3.0.0.
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

This document guides you in upgrading APISIX from version 2.15.x to 3.0.0.

:::note

Upgrading to version 3.0.0 is a major change and it is recommended that you first upgrade to version 2.15.x before you upgrade to 3.0.0.

:::

## Changelog

Please refer to the [3.0.0-beta](https://github.com/apache/apisix/blob/master/CHANGELOG.md#300-beta) and [3.0.0](https://github.com/apache/apisix/blob/master/CHANGELOG.md#300) changelogs for a complete list of incompatible changes and major updates.

## Deployments

From 3.0.0, we no longer support the Alpine-based images of APISIX. You can use the [Debian or CentOS-based images](https://hub.docker.com/r/apache/apisix/tags?page=1&ordering=last_updated) instead.

In addition to the Docker images, we also provide:

1. RPM packages for CentOS 7 and CentOS 8 supporting both AMD64 and ARM64 architectures.
2. DEB packages for Debian 11 (bullseye) supporting both AMD64 and ARM64 architectures.

See the [installation guide](/installation-guide.md) for more details.

3.0.0 also introduces multiple deployment modes. The following modes are supported:

1. [Traditional](./deployment-modes.md#traditional): As the name implies, this is the original deployment mode where one instance of APISIX acts as the control plane and the data plane. Use this deployment mode to keep your deployment similar to older versions.
2. [Decoupled](./deployment-modes.md#decoupled): In this mode, the data plane and the control plane are separated. You can deploy an instance of APISIX either as a control plane or a data plane.
3. [Standalone](./deployment-modes.md#standalone): Using this mode will disable etcd as the configuration center and use a static configuration file instead. You can use this to manage APISIX configuration decaratively or for using other configuration centers.

## Dependencies

All Docker images and binary packages (RPM, DEB) already come with all the necessary dependencies for APISIX.

Some features might require additional Nginx modules in OpenResty and requires you to [build a custom OpenResty distribution (APISIX-Base)](https://github.com/api7/apisix-build-tools).

To run APISIX on a native OpenResty instance use [OpenResty version 1.19.3.2](https://openresty.org/en/download.html#legacy-releases) and above.

## Configurations

There are some major changes to the configuration file in APISIX. You need to update your configuration file (`conf/config.yaml`) to reflect these changes. See the `conf/config-default.yaml` file for the complete changes.

The following attributes in the configuration have been moved:

1. `config_center` is replaced by `config_provider` and moved under `deployment`.
2. `etcd` is moved under `deployment`.
3. The following Admin API configuration attributes are moved to the `admin` attribute under `deployment`:
   1. `admin_key`
   2. `enable_admin_cors`
   3. `allow_admin`
   4. `admin_listen`
   5. `https_admin`
   6. `admin_api_mtls`
   7. `admin_api_version`

The following attributes in the configuration have been replaced:

1. `enable_http2` and `listen_port` under `apisix.ssl` are replaced by `apisix.ssl.listen`. i.e., the below configuration:

   ```yaml title="conf/config.yaml"
   ssl:
     enable_http2: true
     listen_port: 9443
   ```

   changes to:

   ```yaml title="conf/config.yaml"
   ssl:
     listen:
       - port: 9443
         enable_http2: true
   ```

2. `nginx_config.http.lua_shared_dicts` is replaced by `nginx_config.http.custom_lua_shared_dict`. i.e., the below configuration:

   ```yaml title="conf/config.yaml"
   nginx_config:
     http:
       lua_shared_dicts:
         my_dict: 1m
   ```

   changes to:

   ```yaml title="conf/config.yaml"
   nginx_config:
     http:
       custom_lua_shared_dict:
       my_dict: 1m
   ```

   This attribute declares custom shared memory blocks.

3. `etcd.health_check_retry` is replaced by `deployment.etcd.startup_retry`. So this configuration:

   ```yaml title="conf/config.yaml"
   etcd:
     health_check_retry: 2
   ```

   changes to:

   ```yaml title="conf/config.yaml"
   deployment:
     etcd:
       startup_retry: 2
   ```

   This attribute is to configure the number of retries when APISIX tries to connect to etcd.

4. `apisix.port_admin` is replaced by `deployment.admin.admin_listen`. So your previous configuration:

   ```yaml title="conf/config.yaml"
   apisix:
     port_admin: 9180
   ```

   Should be changed to:

   ```yaml title="conf/config.yaml"
   deployment:
     apisix:
       admin_listen:
         ip: 127.0.0.1 # replace with the actual IP exposed
         port: 9180
   ```

   This attribute configures the Admin API listening port.

5. `apisix.real_ip_header` is replaced by `nginx_config.http.real_ip_header`.

6. `enable_cpu_affinity` is set to `false` by default instead of `true`. This is because Nginx's `worker_cpu_affinity` does not count against the cgroup when APISIX is deployed in containers. In such scenarios, it can affect APISIX's behavior when multiple instances are bound to a single CPU.

## Data Compatibility

In 3.0.0, the data structures holding route, upstream, and plugin configuration have been modified and is not fully compatible with 2.15.x. You won't be able to connect an instance of APISIX 3.0.0 to an etcd cluster used by APISIX 2.15.x.

To ensure compatibility, you can try one of the two ways mentioned below:

1. Backup the incompatible data (see [etcdctl snapshot](https://etcd.io/docs/v3.5/op-guide/maintenance/#snapshot-backup)) in etcd and clear it. Convert the backed up data to be compatible with 3.0.0 as mentioned in the below examples and reconfigure it through the Admin API of 3.0.0 instance.
2. Use custom scripts to convert the data structure in etcd to be compatible with 3.0.0.

The following changes have been made in version 3.0.0:

1. `disable` attribute of a plugin has been moved under `_meta`. It enables or disables the plugin. For example, this configuration to disable the `limit-count` plugin:

   ```json
   {
    "plugins":{
        "limit-count":{
            ... // plugin configuration
            "disable":true
        }
    }
   }
   ```

   should be changed to:

   ```json
   {
    "plugins":{
        "limit-count":{
            ... // plugin configuration
            "_meta":{
                "disable":true
            }
        }
    }
   }
   ```

2. `service_protocol` in route has been replaced with `upstream.scheme`. For example, this configuration:

   ```json
   {
     "uri": "/hello",
     "service_protocol": "grpc",
     "upstream": {
       "type": "roundrobin",
       "nodes": {
         "127.0.0.1:1980": 1
       }
     }
   }
   ```

   Should be changed to:

   ```json
   {
     "uri": "/hello",
     "upstream": {
       "type": "roundrobin",
       "scheme": "grpc",
       "nodes": {
         "127.0.0.1:1980": 1
       }
     }
   }
   ```

3. `audience` field from the [authz-keycloak](./plugins/authz-keycloak.md) plugin has been replaced with `client_id`. So this configuration:

   ```json
   {
    "plugins":{
        "authz-keycloak":{
            ... // plugin configuration
            "audience":"Client ID"
        }
    }
   }
   ```

   should be changed to:

   ```json
   {
    "plugins":{
        "authz-keycloak":{
            ... // plugin configuration
            "client_id":"Client ID"
        }
    }
   }
   ```

4. `upstream` attribute from the [mqtt-proxy](./plugins/mqtt-proxy.md) plugin has been moved outside the plugin conference and referenced in the plugin. The configuration below:

   ```json
   {
     "remote_addr": "127.0.0.1",
     "plugins": {
       "mqtt-proxy": {
         "protocol_name": "MQTT",
         "protocol_level": 4,
         "upstream": {
           "ip": "127.0.0.1",
           "port": 1980
         }
       }
     }
   }
   ```

   changes to:

   ```json
   {
     "remote_addr": "127.0.0.1",
     "plugins": {
       "mqtt-proxy": {
         "protocol_name": "MQTT",
         "protocol_level": 4
       }
     },
     "upstream": {
       "type": "chash",
       "key": "mqtt_client_id",
       "nodes": [
         {
           "host": "127.0.0.1",
           "port": 1980,
           "weight": 1
         }
       ]
     }
   }
   ```

5. `max_retry_times` and `retry_interval` fields from the [syslog](./plugins/syslog.md) plugin are replaced `max_retry_count` and `retry_delay` respectively. The configuration below:

   ```json
   {
    "plugins":{
        "syslog":{
            "max_retry_times":1,
            "retry_interval":1,
            ... // other configuration
        }
    }
   }
   ```

   changes to:

   ```json
   {
    "plugins":{
        "syslog":{
            "max_retry_count":1,
            "retry_delay":1,
            ... // other configuration
        }
    }
   }
   ```

6. `scheme` attribute has been removed from the [proxy-rewrite](./plugins/proxy-rewrite.md) plugin and has been added to the upstream. The configuration below:

   ```json
   {
    "plugins":{
        "proxy-rewrite":{
            "scheme":"https",
            ... // other configuration
        }
    },
    "upstream":{
        "nodes":{
            "127.0.0.1:1983":1
        },
        "type":"roundrobin"
    },
    "uri":"/hello"
   }
   ```

   changes to:

   ```json
   {
   "plugins":{
      "proxy-rewrite":{
          ... // other configuration
      }
   },
   "upstream":{
      "scheme":"https",
      "nodes":{
          "127.0.0.1:1983":1
      },
      "type":"roundrobin"
   },
   "uri":"/hello"
   }
   ```

## API

Changes have been made to the Admin API to make it easier to use and be more RESTful.

The following changes have been made:

1. The `count`, `action`, and `node` fields in the response body when querying resources (single and list) are removed and the fields in `node` are moved up to the root of the response body. For example, if you query the `/apisix/admin/routes/1` endpoint of the Admin API in version 2.15.x, you get the response:

   ```json
   {
   "count":1,
   "action":"get",
   "node":{
      "key":"\/apisix\/routes\/1",
      "value":{
          ... // content
      }
   }
   }
   ```

   In 3.0.0, this response body is changes to:

   ```json
   {
   "key":"\/apisix\/routes\/1",
   "value":{
      ... // content
   }
   }
   ```

2. When querying list resources, the `dir` field is removed from the response body, a `list` field to store the data of the list resources and a `total` field to show the total number of list resources are added. For example, if you query the `/apisix/admin/routes` endpoint of the Admin API in version 2.15.x, you get the response:

   ```json
   {
   "action":"get",
   "count":2,
   "node":{
      "key":"\/apisix\/routes",
      "nodes":[
          {
              "key":"\/apisix\/routes\/1",
              "value":{
                  ... // content
              }
          },
          {
              "key":"\/apisix\/routes\/2",
              "value":{
                  ... // content
              }
          }
      ],
      "dir":true
   }
   }
   ```

   In 3.0.0, the response body is:

   ```json
   {
   "list":[
      {
          "key":"\/apisix\/routes\/1",
          "value":{
              ... // content
          }

      },
      {
          "key":"\/apisix\/routes\/2",
          "value":{
              ... // content
          }
      }
   ],
   "total":2
   }
   ```

3. The endpoint to SSL resource is changed from `/apisix/admin/ssl/{id}` to `/apisix/admin/ssls/{id}`.

4. The endpoint to Proto resource is changed from `/apisix/admin/proto/{id}` to `/apisix/admin/protos/{id}`.

5. Admin API port is set to `9180` by default.
