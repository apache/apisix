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

# Query Gateway Elasticsearch Integration Profile

This profile verifies the complete client-to-APISIX-to-Elasticsearch path with a
real Elasticsearch node. APISIX is built from the checked-out source. The
profile is independent from the regular APISIX test suite and can run locally
or in its dedicated integration workflow.

Run:

    cd t/integration/query-gateway-elasticsearch
    make run

The test sends ten requests with one JSON search body:

| Client method | Case | Expected result |
| --- | --- | --- |
| QUERY | first cacheable request | 200, cache MISS |
| QUERY | identical request | 200, cache HIT |
| POST | first read-only cacheable request | 200, cache MISS |
| POST | identical request | 200, cache HIT |
| QUERY | two requests with Authorization | 200, cache bypass |
| POST | two requests with Authorization | 200, cache bypass |
| QUERY | no Content-Type | 400, rejected before upstream |
| POST | no Content-Type | 4xx, rejected by Elasticsearch |

Every request has a distinct `X-Opaque-ID`. The profile persists client,
APISIX access, and Elasticsearch HTTP-trace logs under `artifacts/`, then
requires each expected trace to appear in the client and APISIX logs. It also
requires Elasticsearch traces for cache misses and credential bypasses, and
requires their absence for cache hits and the rejected QUERY request.

Elasticsearch HTTP body tracing is enabled with
`es.insecure_network_trace_enabled`. The data is synthetic; never use this
profile with production data or credentials.
