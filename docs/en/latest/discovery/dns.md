---
title: DNS
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

## service discovery via DNS

Some service discovery system, like Consul, support exposing service information
via DNS. Therefore we can use this way to discover service directly. Both L4 and L7 are supported.

First of all, we need to configure the address of DNS servers:

```yaml
# add this to config.yaml
discovery:
   dns:
     servers:
       - "127.0.0.1:8600"          # use the real address of your dns server
```

Unlike configuring the domain in the Upstream's `nodes` field, service discovery via
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
    "nodes": [
        {"host": "1.1.1.1", "weight": 1},
        {"host": "1.1.1.2", "weight": 1}
    ]
}
```

Note that all the IPs from `test.consul.service` share the same weight.

The resolved records will be cached according to their TTL.
For service whose record is not in the cache, we will query it in the order of `SRV -> A -> AAAA -> CNAME` by default.
When we refresh the cache record, we will try from the last previously successful type.
We can also customize the order by modifying the configuration file.

```yaml
# add this to config.yaml
discovery:
   dns:
     servers:
       - "127.0.0.1:8600"          # use the real address of your dns server
     order:                        # order in which to try different dns record types when resolving
       - last                      # "last" will try the last previously successful type for a hostname.
       - SRV
       - A
       - AAAA
       - CNAME
```

If you want to specify the port for the upstream server, you can add it to the `service_name`:

```json
{
    "id": 1,
    "discovery_type": "dns",
    "service_name": "test.consul.service:1980",
    "type": "roundrobin"
}
```

Another way to do it is via the SRV record, see below.

### SRV record

By using SRV record you can specify the port and the weight of a service.

Assumed you have the SRV record like this:

```
; under the section of blah.service
A       300 IN      A     1.1.1.1
B       300 IN      A     1.1.1.2
B       300 IN      A     1.1.1.3

; name  TTL         type    priority    weight  port
srv     86400 IN    SRV     10          60      1980 A
srv     86400 IN    SRV     20          20      1981 B
```

Upstream configuration like:

```json
{
    "id": 1,
    "discovery_type": "dns",
    "service_name": "srv.blah.service",
    "type": "roundrobin"
}
```

is the same as:

```json
{
    "id": 1,
    "type": "roundrobin",
    "nodes": [
        {"host": "1.1.1.1", "port": 1980, "weight": 60, "priority": -10},
        {"host": "1.1.1.2", "port": 1981, "weight": 10, "priority": -20},
        {"host": "1.1.1.3", "port": 1981, "weight": 10, "priority": -20}
    ]
}
```

Note that two records of domain B split the weight evenly.
For SRV record, nodes with lower priority are chosen first, so the final priority is negative.

As for 0 weight SRV record, the [RFC 2782](https://www.ietf.org/rfc/rfc2782.txt) says:

> Domain administrators SHOULD use Weight 0 when there isn't any server
selection to do, to make the RR easier to read for humans (less
noisy).  In the presence of records containing weights greater
than 0, records with weight 0 should have a very small chance of
being selected.

We treat weight 0 record has a weight of 1 so the node "have a very small chance of
being selected", which is also the common way to treat this type of record.

For SRV record which has port 0, we will fallback to use the upstream protocol's default port.
You can also specify the port in the "service_name" field directly, like "srv.blah.service:8848".
