# Query Gateway Elasticsearch Integration Profile

This profile verifies the complete QUERY to APISIX to POST to Elasticsearch
path using a real Elasticsearch node. It is independent from the regular APISIX
test suite and is intended for local validation or a dedicated integration job.

Run:

    cd t/integration/query-gateway-elasticsearch
    make run

The profile writes client, APISIX, and Elasticsearch logs under artifacts/.
The client sends the same raw HTTP/1.1 QUERY request twice with one
X-Opaque-ID. The first response must be a cache MISS; the second must be a
cache HIT. APISIX must log the client method as QUERY, while the Elasticsearch
HTTP tracer must log one POST /query-gateway-integration/_search request for
the trace ID.

The profile enables Elasticsearch HTTP body tracing with
es.insecure_network_trace_enabled. It uses synthetic data only and must not
be used with production data or credentials.
