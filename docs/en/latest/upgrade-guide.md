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

APISIX adheres to [semantic versioning](https://semver.org/), the format of the version number is: `major.minor.patch`, for example: 2.15.0.

Upgrading to APISIX 3.0.0 is a major version upgrade and we recommend that you upgrade to 2.15.0 first and then to 3.0.0.

## Upgrade to 2.15.0

To upgrade from 2.x to 2.15.0, you can refer to [ChangeLog](../../../CHANGELOG.md#2150), which mainly includes the following:

- Change: incompatible modifications
- Core: core functionality update
- Plugin: plugin updates
- Bugfix: bug fixes

Of particular interest is the Change section, where some important changes are listed:

- We now map the grpc error code OUT_OF_RANGE to http code 400 in grpc-transcode plugin: [#7419](https://github.com/apache/apisix/pull/7419)
- Rename health_check_retry configuration in etcd section of `config-default.yaml` to startup_retry: [#7304](https://github.com/apache/apisix/pull/7304)
- Remove `upstream.enable_websocket` which is deprecated since 2020: [#7222](https://github.com/apache/apisix/pull/7222)
- To adapt the change of OpenTelemetry spec, the default port of OTLP/HTTP is changed to 4318: [#7007](https://github.com/apache/apisix/pull/7007)
- change(syslog): correct the configuration [#6551](https://github.com/apache/apisix/pull/6551)
- change(server-info): use a new approach(keepalive) to report DP info [#6202](https://github.com/apache/apisix/pull/6202)
- change(admin): empty nodes should be encoded as array [#6384](https://github.com/apache/apisix/pull/6384)
- change(prometheus): replace wrong apisix_nginx_http_current_connections{state="total"} label [#6327](https://github.com/apache/apisix/pull/6327)
- change: don't expose public API by default & remove plugin interceptor [#6196](https://github.com/apache/apisix/pull/6196)
- change(serverless): rename "balancer" phase to "before_proxy" [#5992](https://github.com/apache/apisix/pull/5992)
- change: don't promise to support Tengine [#5961](https://github.com/apache/apisix/pull/5961)
- change: enable HTTP when stream proxy is set and enable_admin is true [#5867](https://github.com/apache/apisix/pull/5867)
- change(wolf-rbac): change default port number and add `authType` parameter to documentation [#5477](https://github.com/apache/apisix/pull/5477)
- change(debug): move 'enable_debug' form config.yaml to debug.yaml [#5046](https://github.com/apache/apisix/pull/5046)
- change: use a new name to customize lua_shared_dict in nginx.conf [#5030](https://github.com/apache/apisix/pull/5030)
- change: drop the support of shell script installation [#4985](https://github.com/apache/apisix/pull/4985)

### How to upgrade according to Change

You need to understand what is in the ChangeLog and then decide if you need to change your configuration based on your actual situation.

#### Update configuration file

Using [#7304](https://github.com/apache/apisix/pull/7304) as an example, you can search for `etcd.health_check_retry` in the configuration file, and if there is a corresponding config item, then after upgrading APISIX to version 2.15.0 you need to change this config item to `startup_retry`. If there is no corresponding config item in your configuration file, then you do not need to make any changes.

#### Update data structure

Using [#6551](https://github.com/apache/apisix/pull/6551) as an example, if you are using the syslog plugin and have the `max_retry_times` and `retry_interval` properties, then after upgrading to 2.15.0, you need to change the `syslog` plugin properties to `max_retry_times` and `retry_interval` to `retry_delay`. If the syslog plugin is used in many routes, then you will need to update these properties manually or write your scripts to change them consistently. Currently, we do not provide scripts to help you do this.

#### Update business logic

Using [#6196](https://github.com/apache/apisix/pull/6196) as an example, if you have developed an admin interface based on the Admin API that fits your business system, or if you are using the public API of an open source plugin, or if you are developing your own private plugin and using the public API, then you need to understand the Change and decide if you need to change your code based on your situation. Then you need to decide whether you need to modify your code according to your actual situation.

For example, if you use the jwt-auth plugin and use its public API (default is `/apisix/plugin/jwt/sign`) to issue jwt, then after upgrading to 2.15.0, you need to configure a route for the jwt-auth plugin's public API, and then change the request address in your code to address of this route. See [register public api](./plugin-develop.md#register-public-api).

## Upgrade to 3.0.0

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

APISIX is configured to override the default `conf/config-default.yaml` with the contents of custom `conf/config.yaml`, or if a config item item does not exist in `conf/config.yaml`, then use the config item in `conf/config-default.yaml`. In 3.0.0, we adjusted `conf/config-default.yaml`.

###### Move config items

From version 2.15.0 to 3.0.0, the location of some config items in `conf/config-default.yaml` has been moved. If you are using these config items, then you need to move them to the new location.

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

You can find the exact new location of these config items in `conf/config-default.yaml`.

###### Update config items

Some config items have been removed in 3.0.0 and replaced with new config items. If you are using these config items, then you need to update them to the new config items.

Adjustment content:

  * Removed `enable_http2` and `listen_port` from `apisix.ssl` and replaced with `apisix.ssl.listen`

  If you have this config item in `conf/config.yaml` like:

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

  * Removed `nginx_config.http.lua_shared_dicts` and replaced with `nginx_config.http.custom_lua_shared_dict`, this config item is used to declare custom shared memory blocks. If you have this config item in `conf/config.yaml` like:

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

  * Removed `etcd.health_check_retry` and replaced with `deployment.etcd.startup_retry`, this config item is used to configure the number of retries when APISIX starts to connect to etcd. If you have this config item in `conf/config.yaml` like:

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

  * Removed `apisix.port_admin` and replaced with `deployment.admin.admin_listen`, this config item is used to configure the Admin API listening port. If you have this config item in `conf/config.yaml` like:

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

  * Change the default value of `enable_cpu_affinity` to `false`, this configuration is used to bind worker processes to CPU cores. If you need to bind worker processes to CPU cores, then you need to set this configuration to `true` in `conf/config.yaml`
  * Removed `apisix.real_ip_header` and replaced with `nginx_config.http.real_ip_header`

##### Data Migration

If you need to backup and restore your data, you can use the backup and restore function of ETCD, refer to [etcdctl snapshot](https://etcd.io/docs/v3.5/op-guide/maintenance/#snapshot-backup).

#### Data Compatible

In 3.0.0, we have adjusted some of the data structures that affect the routing, upstream, and plugin data of APISIX. The data is not fully compatible between version 3.0.0 and version 2.15.0. You cannot use APISIX version 3.0.0 to connect directly to the ETCD cluster used by APISIX version 2.15.0.

In order to keep the data compatible, there are two ways, for reference only.

  1. Review the data in ETCD, back up the incompatible data and then clear it, convert the backed up data structure to that of version 3.0.0, and restore the data through the Admin API of version 3.0.0
  2. Review the data in ETCD, write scripts to convert the data structure of version 2.15.0 into the data structure of version 3.0.0 in batch

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

  In 3.0.0, the data structure of this plugin should be transformed to

  ```json
  {
      "plugins":{
          "limit-count":{
              ... // 插件配置
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
              ... // 插件配置
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
              ... // 插件配置
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
              ... // 其他配置
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
            ... // 其他配置
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

We have adjusted the response format of Admin API, refer to [New Admin API response format](../../../CHANGELOG.md#new-admin-api-response-format), and also adjusted the port of Admin API to 9180.
