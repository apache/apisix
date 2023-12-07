---
title: 升级指南
keywords:
  - APISIX
  - APISIX 升级指南
  - APISIX 版本升级
description: 本文档将引导你了解如何升级 APISIX 版本。
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

## APISIX 的版本升级方式

APISIX 的版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

升级到 APISIX 3.0.0 是一个重大的版本升级，我们建议您先升级到 2.15.x，然后再升级到 3.0.0。

## 从 2.15.x 升级到 3.0.0

### 升级注意事项和重大更新

在升级之前，请查看 [3.0.0-beta](./CHANGELOG.md#300-beta) 和 [3.0.0](./CHANGELOG.md#300) 中的 Change 部分，以了解 3.0.0 版本的不兼容的修改与重大更新。

#### 部署

基于 alpine 的镜像已不再支持，如果你使用了 alpine 的镜像，那么你需要将镜像替换为基于 debian/centos 的镜像。

目前，我们提供了：

- 基于 debian/centos 的镜像，你可以在 [DockerHub](https://hub.docker.com/r/apache/apisix/tags?page=1&ordering=last_updated) 上找到它们
- CentOS 7 和 CentOS 8 的 RPM 包，支持 AMD64 和 ARM64 架构，可参考文章[通过 RPM 仓库安装](./installation-guide.md#通过-rpm-仓库安装)
- Debian 11(bullseye) 的 DEB 包，支持 AMD64 和 ARM64 架构，可参考文章[通过 DEB 仓库安装](./installation-guide.md#通过-deb-仓库安装)

3.0.0 对部署模式进行了重大更新，具体如下：

- 支持数据面与控制面分离的部署模式，具体可参考 [Decoupled](../../en/latest/deployment-modes.md#decoupled)
- 如在使用中仍需沿用原来的部署模式，那么可以使用部署模式中的 `traditional` 模式，并且更新配置文件，具体可参考 [Traditional](../../en/latest/deployment-modes.md#traditional)
- 支持 Standalone 模式，需要更新配置文件，具体可参考 [Standalone](../../en/latest/deployment-modes.md#standalone)

#### 依赖项

如果你使用提供的二进制包（Debian 和 RHEL）或者镜像，则它们已经捆绑了 APISIX 所有必要的依赖项，你可以跳过本节。

APISIX 的一些特性需要在 OpenResty 中引入额外的 NGINX 模块。如果要使用这些功能，你需要构建一个自定义的 OpenResty 发行版（APISIX-Runtime）。你可以参考 [api7/apisix-build-tools](https://github.com/api7/apisix-build-tools) 中的代码，构建自己的 APISIX-Runtime 环境。

如果你希望 APISIX 运行在原生的 OpenResty 上，这种情况下将只支持运行在 OpenResty 1.19.3.2 及以上的版本。

#### 迁移

##### 静态配置迁移

APISIX 的配置方式是用自定义的 `conf/config.yaml` 中的内容覆盖默认的 `conf/config-default.yaml`，如果某个配置项在 `conf/config.yaml` 中不存在，那么就使用 `conf/config-default.yaml` 中的配置。在 3.0.0 中，我们调整了 `conf/config-default.yaml` 配置文件中的部分细节，具体内容如下。

###### 移动配置项

从 2.15.x 到 3.0.0 版本，在 `conf/config-default.yaml` 有一些配置项的位置被移动了。如果你使用了这些配置项，那么你需要将它们移动到新的位置。

调整内容：

  * `config_center` 功能改由 `deployment` 中的 `config_provider` 实现
  * `etcd` 字段整体迁移到 `deployment` 中
  * 以下的 Admin API 配置移动到 `deployment` 中的 `admin` 字段
    - admin_key
    - enable_admin_cors
    - allow_admin
    - admin_listen
    - https_admin
    - admin_api_mtls
    - admin_api_version

你可以在 `conf/config-default.yaml` 中找到这些配置的新的确切位置。

###### 更新配置项

某些配置在 3.0.0 中被移除了，并被新的配置项替代。如果你使用了这些配置项，那么你需要将它们更新为新的配置项。

调整内容：

  * 去除 `apisix.ssl.enable_http2` 和 `apisix.ssl.listen_port`，使用 `apisix.ssl.listen` 替代。

  如果在 `conf/config.yaml` 中有这样的配置：

  ```yaml
    ssl:
      enable_http2: true
      listen_port: 9443
  ```

  则在 3.0.0 版本中需要转换成如下所示：

  ```yaml
    ssl:
      listen:
        - port: 9443
          enable_http2: true
  ```

  * 去除 `nginx_config.http.lua_shared_dicts`，用 `nginx_config.http.custom_lua_shared_dict` 替代，这个配置用于声明自定义插件的共享内存。

  如果在 `conf/config.yaml` 中有这样的配置：

  ```yaml
  nginx_config:
    http:
      lua_shared_dicts:
        my_dict: 1m
  ```

  则在 3.0.0 版本中需要转换成如下所示：

  ```yaml
  nginx_config:
    http:
      custom_lua_shared_dict:
        my_dict: 1m
  ```

  * 去除 `etcd.health_check_retry`，用 `deployment.etcd.startup_retry` 替代，这个配置用于在启动时，重试连接 etcd 的次数。

  如果在 `conf/config.yaml` 中有这样的配置：

  ```yaml
  etcd:
    health_check_retry: 2
  ```

  则在 3.0.0 版本中需要转换成如下所示：

  ```yaml
  deployment:
    etcd:
      startup_retry: 2
  ```

  * 去除 `apisix.port_admin`，用 `deployment.apisix.admin_listen` 替代。

  如果在 `conf/config.yaml` 中有这样的配置：

  ```yaml
  apisix:
    port_admin: 9180
  ```

  则在 3.0.0 中需要转换成如下所示：

  ```yaml
  deployment:
    apisix:
      admin_listen:
        ip: 127.0.0.1 # 替换成实际暴露的 IP
        port: 9180
  ```

  * 修改 `enable_cpu_affinity` 的默认值为 `false`。主要是因为越来越多的用户通过容器部署 APISIX，由于 Nginx 的 worker_cpu_affinity 不计入 cgroup，默认启用 worker_cpu_affinity 会影响 APISIX 的行为，例如多个实例会被绑定到一个 CPU 上。为了避免这个问题，我们在 `conf/config-default.yaml` 中默认禁用 `enable_cpu_affinity` 选项。
  * 去除 `apisix.real_ip_header`，用 `nginx_config.http.real_ip_header` 替代

##### 数据迁移

如果你需要备份与恢复数据，可以利用 ETCD 的备份与恢复功能，参考 [etcdctl snapshot](https://etcd.io/docs/v3.5/op-guide/maintenance/#snapshot-backup)。

#### 数据兼容

在 3.0.0 中，我们调整了部分数据结构，这些调整影响到 APISIX 的路由、上游、插件等数据。3.0.0 版本与 2.15.x 版本之间数据不完全兼容。因此，你无法使用 3.0.0 版本的 APISIX 直接连接到 2.15.x 版本 APISIX 使用的 ETCD 集群。

为了保持数据兼容，有两种方式，仅供参考：

  1. 梳理 ETCD 中的数据，将不兼容的数据备份然后清除，将备份的数据结构转换成 3.0.0 版本的数据结构，通过 3.0.0 版本的 Admin API 来恢复数据
  2. 梳理 ETCD 中的数据，编写脚本，将 2.15.x 版本的数据结构批量转换成 3.0.0 版本的数据结构

数据层面调整内容如下。

  * 将插件配置的元属性 `disable` 移动到 `_meta` 中。

  `disable` 表示该插件的启用/禁用状态，如果在 ETCD 中存在这样的数据结构：

  ```json
  {
      "plugins":{
          "limit-count":{
              ... // 插件配置
              "disable":true
          }
      }
  }
  ```

  则在 3.0.0 版本中，这个插件的数据结构应该变成如下所示：

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

  注意：`disable` 是插件的元配置，该调整对所有插件配置生效，不仅仅是 `limit-count` 插件。

  * 去除路由的 `service_protocol` 字段，使用 `upstream.scheme` 替代。

  如果在 ETCD 中存在这样的数据结构：

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

  则在 3.0.0 版本中，这个路由的数据结构应该变成如下所示：

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

  * 去除 `authz-keycloak` 插件中的 `audience` 字段，使用 `client_id` 替代。

  如果在 ETCD 中 `authz-keycloak` 的插件配置存在这样的数据结构：

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

  则在 3.0.0 中，这个路由的数据结构应该变成如下所示：

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

  * 去除 `mqtt-proxy` 插件中的 `upstream`，在插件外部配置 `upstream`，并在插件中引用。

  如果在 ETCD 中 `mqtt-proxy` 的插件配置存在这样的数据结构：

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

  则在 3.0.0 版本中，这个插件的数据结构应该变成如下所示：

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

  * 去除 `syslog` 插件中的 `max_retry_times` 和 `retry_interval` 字段，使用 `max_retry_count` 和 `retry_delay` 替代。

  如果在 ETCD 中 `syslog` 的插件配置存在这样的数据结构：

  ```json
  {
      "plugins":{
          "syslog":{
              "max_retry_times":1,
              "retry_interval":1,
              ... // 其他配置
          }
      }
  }
  ```

  则在 3.0.0 版本中，这个插件的数据结构应该变成如下所示：

  ```json
  {
      "plugins":{
          "syslog":{
              "max_retry_count":1,
              "retry_delay":1,
              ... // 其他配置
          }
      }
  }
  ```

  * 去除 `proxy-rewrite` 插件中的 `scheme` 字段，在配置上游时，用 `upstream.scheme` 替代。

  如果在 ETCD 中 `proxy-rewrite` 的插件配置存在这样的数据结构：

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

  则在 3.0.0 版本中，这个插件的数据结构应该变成如下所示：

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

在 3.0.0 版本中，我们对 Admin API 也进行了一些调整。使得 Admin API 更加易用，更加符合 RESTful 的设计理念，具体调整内容如下。

  * 操作资源时（包括查询单个资源和列表资源），删除了响应体中的 `count`、`action` 和 `node` 字段，并将 `node` 中的内容提升到响应体的根节点。

  在 2.x 版本中，通过 Admin API 查询 `/apisix/admin/routes/1` 的响应格式是这样的：

  ```json
  {
    "count":1,
    "action":"get",
    "node":{
        "key":"\/apisix\/routes\/1",
        "value":{
            ... // 配置内容
        }
    }
  }
  ```

  在 3.0.0 版本中，通过 Admin API 查询 `/apisix/admin/routes/1` 资源的响应格式调整为如下所示：

  ```json
  {
    "key":"\/apisix\/routes\/1",
    "value":{
        ... // 配置内容
    }
  }
  ```

  * 查询列表资源时，删除 `dir` 字段，新增 `list` 字段，存放列表资源的数据；新增 `total` 字段，存放列表资源的总数。

  在 2.x 版本中，通过 Admin API 查询 `/apisix/admin/routes` 的响应格式是这样的：

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
                    ... // 配置内容
                }
            },
            {
                "key":"\/apisix\/routes\/2",
                "value":{
                    ... // 配置内容
                }
            }
        ],
        "dir":true
    }
  }
  ```

  在 3.0.0 版本中，通过 Admin API 查询 `/apisix/admin/routes` 资源的响应格式调整为如下所示：

  ```json
  {
    "list":[
        {
            "key":"\/apisix\/routes\/1",
            "value":{
                ... // 配置内容
            }

        },
        {
            "key":"\/apisix\/routes\/2",
            "value":{
                ... // 配置内容
            }
        }
    ],
    "total":2
  }
  ```

  * 调整 ssl 资源的请求路径，从 `/apisix/admin/ssl/{id}` 调整为 `/apisix/admin/ssls/{id}`。

  在 2.x 版本中，通过 Admin API 操作 ssl 资源是这样的：

  ```shell
  curl -i http://{apisix_listen_address}/apisix/admin/ssl/{id}
  ```

  在 3.0.0 版本中，通过 Admin API 操作 ssl 资源调整为如下所示：

  ```shell
  curl -i http://{apisix_listen_address}/apisix/admin/ssls/{id}
  ```

  * 调整 proto 资源的请求路径，从 `/apisix/admin/proto/{id}` 调整为 `/apisix/admin/protos/{id}`。

  在 2.x 版本中，通过 Admin API 操作 proto 资源是这样的：

  ```shell
  curl -i http://{apisix_listen_address}/apisix/admin/proto/{id}
  ```

  在 3.0.0 版本中，通过 Admin API 操作 proto 资源调整为如下所示：

  ```shell
  curl -i http://{apisix_listen_address}/apisix/admin/protos/{id}
  ```

除以上内容外，我们也将 Admin API 的端口调整为 9180。

## 总结

Apache APISIX 3.0.0 版本的发布，将产品的更多细节迭代了一大步。由于大版本的更新迭代会导致一些配置与数据也相应进行调整，为此我们为您整理了这份 APISIX 升级指南。希望对各位在使用 APISIX 的过程中，对于版本的更新操作也更得心应手。

如果您有任何问题或意见，欢迎随时在社区进行交流。
