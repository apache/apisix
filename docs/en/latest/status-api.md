---
title: Status API
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

In Apache APISIX, the status API is used to:

* Check if APISIX has successfully started and running correctly.
* Check if all of the workers have received and loaded the configuration.

To change the default endpoint (`127.0.0.1:7085`) of the Status API server, change the `ip` and `port` in the `status` section in your configuration file (`conf/config.yaml`):

```yaml
apisix:
  status:
    ip: "127.0.0.1"
    port: 7085
```

This API can be used to perform readiness probes on APISIX before APISIX starts receiving user requests.

### GET /status

Returns a JSON reporting the status of APISIX workers. If APISIX is not running, the request will error out while establishing TCP connection. Otherwise this endpoint will always return ok if request reaches a running worker.

```json
{
  "status": "ok"
}
```

### GET /status/ready

Returns `ok` when all workers have loaded the configuration, otherwise returns the specific error with `503` error code. Below are specific examples.

When all workers have loaded the configuration:

```json
{
  "status": "ok"
}
```

When 1 workers has't been initialised:

```json
{
  "status": "error",
  "error": "worker count: 16 but status report count: 15"
}
```

When a particular worker hasn't loaded the configuration:

```json
{
  "error": "worker id: 9 has not received configuration",
  "status": "error"
}
```
