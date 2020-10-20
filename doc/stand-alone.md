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

[Chinese](zh-cn/stand-alone.md)

## Stand-alone mode

Turning on the APISIX node in Stand-alone mode will no longer use the default etcd as the configuration center.

This method is more suitable for two types of users:
1. kubernetes(k8s)：Declarative API that dynamically updates the routing rules with a full yaml configuration.
2. Different configuration centers: There are many implementations of the configuration center, such as Consul, etc., using the full yaml file for intermediate conversion.

The routing rules in the `conf/apisix.yaml` file are loaded into memory immediately after the APISIX node service starts. And every time interval (default 1 second), will try to detect whether the file content is updated, if there is an update, reload the rule.

*Note*: When reloading and updating routing rules, they are all hot memory updates, and there will be no replacement of working processes, it is a hot update.

To enable Stand-alone model, we can set `apisix.config_center` to `yaml` in file `conf/config.yaml`.

Refer to the example below:

```yaml
apisix:
  # ...
  config_center: yaml   # etcd: use etcd to store the config value
                        # yaml: fetch the config value from local yaml file
                        # `/your_path/conf/apisix.yaml`
```

In addition, since the current Admin API is based on the etcd configuration center solution, the Admin API will not actually work when the Stand-alone mode is enabled.

## How to config rules

All of the rules are stored in one file which named `conf/apisix.yaml`,
the APISIX will check if this file has any changed every second.
If the file changed and we found `#END` at the end of the file,
APISIX will load the rules in this file and update to memory of APISIX.

Here is a mini example:

```yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
```

*NOTE*: APISIX will not load the rules into memory from file `conf/apisix.yaml` if there is no `#END` at the end.

#### How to config Router

Single Router：

```yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
```

Multiple Router：

```yaml
routes:
  -
    uri: /hello
    upstream:
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
  -
    uri: /hello2
    upstream:
        nodes:
            "127.0.0.1:1981": 1
        type: roundrobin
#END
```


#### How to config Router + Service

```yml
routes:
    -
        uri: /hello
        service_id: 1
services:
    -
        id: 1
        upstream:
            nodes:
                "127.0.0.1:1980": 1
            type: roundrobin
#END
```

#### How to config Router + Upstream

```yml
routes:
    -
        uri: /hello
        upstream_id: 1
upstreams:
    -
        id: 1
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
```

#### How to config Router + Service + Upstream

```yml
routes:
    -
        uri: /hello
        service_id: 1
services:
    -
        id: 1
        upstream_id: 2
upstreams:
    -
        id: 2
        nodes:
            "127.0.0.1:1980": 1
        type: roundrobin
#END
```

