---
title: APISIX
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

## Plugin Loading Process

![flow-load-plugin](../../../assets/images/flow-load-plugin.png)

## Plugin Hierarchy Structure

![flow-plugin-internal](../../../assets/images/flow-plugin-internal.png)

## Configure APISIX

There are two methods to configure APISIX: directly change `conf/config.yaml`, or add file path argument using `-c` or `--config` flag when start APISIX like `apisix start -c <path string>`

For example, set the default listening port of APISIX to 8000, and keep other configurations as default. The configuration in `config.yaml` should be like this:

```yaml
apisix:
  node_listen: 8000 # APISIX listening port
```

Set the default listening port of APISIX to 8000, set the `etcd` address to `http://foo:2379`,
and keep other configurations as default. The configuration in `config.yaml` should be like this:

```yaml
apisix:
  node_listen: 8000 # APISIX listening port

etcd:
  host: "http://foo:2379" # etcd address
```

Other default configurations can be found in the `conf/config-default.yaml` file, which is bound to the APISIX source code. **Never** manually modify the `conf/config-default.yaml` file. If you need to customize any configuration, you should update the `config.yaml` file.

**Note** `APISIX` will generate `conf/nginx.conf` file automatically, so please _DO NOT EDIT_ `conf/nginx.conf` file too.
