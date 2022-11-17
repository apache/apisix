---
title: Upgrade Guide
keywords:
  - APISIX
  - APISIX Upgrade Guide
  - APISIX Version Upgrade
description: This document will guide on you how to upgrade your APISIX version.
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

## Upgrade path for APISIX

APISIX adheres to [semantic versioning](https://semver.org/).

Upgrading to APISIX 3.0.0 is a major version upgrade and we recommend that you upgrade to 2.15.x first and then to 3.0.0.

## From 2.15.x upgrade to 3.0.0

### Upgrade Notes and Major Updates

Before upgrading, please check the [3.0.0-beta](../../../CHANGELOG.md#300-beta) and [3.0.0](../../../CHANGELOG.md#300) in the Change section for incompatible changes and major updates for version 3.0.0.

#### Deploy

The alpine-based image is no longer supported, so if you are using the alpine image, you will need to replace it with a debian/centos-based image.

Currently, we provide:

- debian/centos-based images, you can find them on [DockerHub](https://hub.docker.com/r/apache/apisix/tags?page=1&ordering=last_updated)
- RPM packages for CentOS 7 and CentOS 8, supporting amd64 and arm64 architectures, refer to [install via RPM repository](./installation-guide.md#installation-via-rpm-repository)
- DEB package for Debian 11 (bullseye), supporting amd64 and arm64 architectures, see [install via DEB repository](./installation-guide.md#installation-via-deb-repository)

3.0.0 makes major updates to the deployment model, as follows:

- Support the deployment mode of separating data plane and control plane, please refer to [Decoupled](./deployment-modes.md#decoupled)
- If you need to continue using the original deployment mode, then you can use the `traditional` mode in the deployment mode and update the configuration file, please refer to [Traditional](./deployment-modes.md#traditional)
- Support Standalone mode, need to update the configuration file, please refer to [Standalone](./deployment-modes.md#standalone)

#### Dependencies

If you use the provided binary packages (Debian and RHEL), or images, then they already bundle all the necessary dependencies for APISIX and you can skip this section.

Some features of APISIX require additional NGINX modules to be introduced in OpenResty. To use these features, you need to build a custom OpenResty distribution (APISIX-Base). You can build your own APISIX-Base environment by referring to the code in [api7/apisix-build-tools](https://github.com/api7/apisix-build-tools).

If you want APISIX to run on native OpenResty, then only OpenResty 1.19.3.2 and above are supported.

#### Migrations

##### Static configuration migration

APISIX is configured to override the default `conf/config-default.yaml` with the contents of custom `conf/config.yaml`, or if a configuration does not exist in `conf/config.yaml`, then use the configuration in `conf/config-default.yaml`. In 3.0.0, we adjusted `conf/config-default.yaml`.

###### Move configuration

From version 2.15.x to 3.0.0, the location of some configuration in `conf/config-default.yaml` has been moved. If you are using these configuration, then you need to move them to the new location.

Adjustment content:

  * `config_center` is now implemented by `config_provider` under `deployment`
  * The `etcd` field is moved to `deployment`.
  * The following Admin API configuration is moved to the `admin` field under `deployment`
    - admin_key
    - enable_admin_cors
    - allow_admin
    - admin_listen
    - https_admin
    - admin_api_mtls
    - admin_api_version

You can find the exact new location of these configuration in `conf/config-default.yaml`.

###### Update configuration

Some configuration have been removed in 3.0.0 and replaced with new configuration. If you are using these configuration, then you need to update them to the new configuration.

Adjustment content:

  * Removed `enable_http2` and `listen_port` from `apisix.ssl` and replaced with `apisix.ssl.listen`

  If you have this configuration in `conf/config.yaml` like:

  ```yaml
    ssl:
      enable_http2: true
      listen_port: 9443
  ```

  Then you need to change it to:

  ```yaml
    ssl:
      listen:
        - port: 9443
          enable_http2: true
  ```

  * Removed `nginx_config.http.lua_shared_dicts` and replaced with `nginx_config.http.custom_lua_shared_dict`, this configuration is used to declare custom shared memory blocks. If you have this configuration in `conf/config.yaml` like:

  ```yaml
  nginx_config:
    http:
      lua_shared_dicts:
        my_dict: 1m
  ```

  Then you need to change it to:

  ```yaml
  nginx_config:
    http:
      custom_lua_shared_dict:
        my_dict: 1m
  ```

  * Removed `etcd.health_check_retry` and replaced with `deployment.etcd.startup_retry`, this configuration is used to configure the number of retries when APISIX starts to connect to etcd. If you have this configuration in `conf/config.yaml` like:

  ```yaml
  etcd:
    health_check_retry: 2
  ```

  Then you need to change it to:

  ```yaml
  deployment:
    etcd:
      startup_retry: 2
  ```

  * Removed `apisix.port_admin` and replaced with `deployment.admin.admin_listen`, this configuration is used to configure the Admin API listening port. If you have this configuration in `conf/config.yaml` like:

  ```yaml
  apisix:
    port_admin: 9180
  ```

  Then you need to change it to:

  ```yaml
  deployment:
    apisix:
      admin_listen:
        ip: 127.0.0.1 # replace with the actual IP exposed
        port: 9180
  ```

  * Change the default value of `enable_cpu_affinity` to `false`. Reason: More and more users are deploying APISIX via containers. Since Nginx's worker_cpu_affinity does not count against the cgroup, enabling worker_cpu_affinity by default can affect APISIX behavior, for example, if multiple instances are bound to a single CPU. To avoid this problem, we disable the `enable_cpu_affinity` option by default in `conf/config-default.yaml`.
  * Removed `apisix.real_ip_header` and replaced with `nginx_config.http.real_ip_header`

##### Data Migration

If you need to backup and restore your data, you can use the backup and restore function of ETCD, refer to [etcdctl snapshot](https://etcd.io/docs/v3.5/op-guide/maintenance/#snapshot-backup).

#### Data Compatible

In 3.0.0, we have adjusted some of the data structures that affect the routing, upstream, and plugin data of APISIX. The data is not fully compatible between version 3.0.0 and version 2.15.x. You cannot use APISIX version 3.0.0 to connect directly to the ETCD cluster used by APISIX version 2.15.x.

In order to keep the data compatible, there are two ways, for reference only.

  1. Review the data in ETCD, back up the incompatible data and then clear it, convert the backed up data structure to that of version 3.0.0, and restore the data through the Admin API of version 3.0.0
  2. Review the data in ETCD, write scripts to convert the data structure of version 2.15.x into the data structure of version 3.0.0 in batch

Adjustment content:

  * Moved `disable` of the plugin configuration under `_meta`

  `disable` indicates the enable/disable status of the plugin

  If such a data structure exists in ETCD

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

  In 3.0.0, the data structure of this plugin should be transformed to

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

  Note: `disable` is the meta-configuration of the plugin, and this adjustment takes effect for all plugin configurations, not just the `limit-count` plugin.

  * Removed `service_protocol` from the Route, and replaced it with `upstream.scheme`

  If such a data structure exists in ETCD

  ```json
  {
      "uri":"/hello",
      "service_protocol":"grpc",
      "upstream":{
          "type":"roundrobin",
          "nodes":{
              "127.0.0.1:1980":1
          }
      }
  }
  ```

  In 3.0.0, the data structure of this plugin should be transformed to

  ```json
  {
      "uri":"/hello",
      "upstream":{
          "type":"roundrobin",
          "scheme":"grpc",
          "nodes":{
              "127.0.0.1:1980":1
          }
      }
  }
  ```

  * Removed `audience` field from authz-keycloak, and replaced it with `client_id`

  If such a data structure of authz-keycloak plugin exists in ETCD

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

  In 3.0.0, the data structure of this plugin should be transformed to

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

* Removed `upstream` field from mqtt-proxy, and configure `upstream` outside the plugin and reference it in the plugin

  If such a data structure of mqtt-proxy plugin exists in ETCD

  ```json
  {
      "remote_addr":"127.0.0.1",
      "plugins":{
          "mqtt-proxy":{
              "protocol_name":"MQTT",
              "protocol_level":4,
              "upstream":{
                  "ip":"127.0.0.1",
                  "port":1980
              }
          }
      }
  }
  ```

  In 3.0.0, the data structure of this plugin should be transformed to

  ```json
  {
      "remote_addr":"127.0.0.1",
      "plugins":{
          "mqtt-proxy":{
              "protocol_name":"MQTT",
              "protocol_level":4
          }
      },
      "upstream":{
          "type":"chash",
          "key":"mqtt_client_id",
          "nodes":[
              {
                  "host":"127.0.0.1",
                  "port":1980,
                  "weight":1
              }
          ]
      }
  }
  ```

  * Removed `max_retry_times` and `retry_interval` fields from syslog, and replaced them with `max_retry_count` and `retry_delay`

    If such a data structure of syslog plugin exists in ETCD

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

  In 3.0.0, the data structure of this plugin should be transformed to

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

  * The `scheme` field has been removed from proxy-rewrite, and the `scheme` field has been added to upstream

    If such a data structure of proxy-rewrite plugin exists in ETCD

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

  In 3.0.0, the data structure of this plugin should be transformed to

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

#### Admin API

We have made some tweaks to the Admin API that are designed to make it easier to use and more in line with RESTful design ideas.

Adjustment content:

  * When operating resources (both single resources and list resources), the `count`, `action` and `node` fields in the response body are removed and the contents of `node` are moved up to the root of the response body

  In version 2.x, the response format for querying `/apisix/admin/routes/1` via the Admin API is

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

  In 3.0.0, the response format for querying the `/apisix/admin/routes/1` resource via the Admin API is

  ```json
  {
    "key":"\/apisix\/routes\/1",
    "value":{
        ... // content
    }
  }
  ```

  * When querying the list resources, delete the `dir` field, add a new `list` field to store the data of the list resources, and add a new `total` field to store the total number of list resources

  In version 2.x, the response format for querying `/apisix/admin/routes` via the Admin API is

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

  In 3.0.0, the response format for querying the `/apisix/admin/routes` resource via the Admin API is

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

  * Adjust the request path of the ssl resource from `/apisix/admin/ssl/{id}` to `/apisix/admin/ssls/{id}`

  In version 2.x, operating with ssl resources via the Admin API

  ```shell
  curl -i http://{apisix_listen_address}/apisix/admin/ssl/{id}
  ```

  In 3.0.0, operating with ssl resources via the Admin API

  ```shell
  curl -i http://{apisix_listen_address}/apisix/admin/ssls/{id}
  ```

  * Adjust the request path of the proto resource from `/apisix/admin/proto/{id}` to `/apisix/admin/protos/{id}`

  In version 2.x, operating with proto resources via the Admin API

  ```shell
  curl -i http://{apisix_listen_address}/apisix/admin/proto/{id}
  ```

  In 3.0.0, operating with proto resources via the Admin API

  ```shell
  curl -i http://{apisix_listen_address}/apisix/admin/protos/{id}
  ```

We also adjusted the Admin API port to 9180.
