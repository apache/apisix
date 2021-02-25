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

* [service discovery via DNS](#service-discovery-via-dns)

## service discovery via DNS

Some service discovery system, like Consul, support exposing service information
via DNS. Therefore we can use this way to discover service directly.

First of all, we need to configure the address of DNS servers:

```yaml
# add this to config.yaml
discovery:
   dns:
     servers:
       - "127.0.0.1:8600"          # use the real address of your dns server
```

Unlike configurating domain in the Upstream's `nodes` field, service discovery via
DNS will return all records. For example, with upstream configuration:

```json
{
    "id": 1,
    "discovery_type": "dns",
    "service_name": "test.consul.service",
    "type": "roundrobin"
}
```

and `test.consul.service` be resolved as `1.1.1.1` and `1.1.1.2`, this result will be the same as:

```json
{
    "id": 1,
    "type": "roundrobin",
    "nodes": {
        {"host": "1.1.1.1", "weight": 1},
        {"host": "1.1.1.2", "weight": 1}
    }
}
```

Note that all the IPs from `test.consul.service` share the same weight.

If a service has both A and AAAA records, A record is preferred.
Currently we support A / AAAA records, SRV has not been supported yet.

If you want to specify the port for the upstream server, you can add it to the `service_name`:

```json
{
    "id": 1,
    "discovery_type": "dns",
    "service_name": "test.consul.service:1980",
    "type": "roundrobin"
}
```
