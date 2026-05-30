<!--
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
-->

# Apache APISIX — Threat Model

> **This is a maintainer-stewarded threat model owned by the
> Apache APISIX PMC.** It follows the rubric at
> <https://gist.github.com/potiuk/da14a826283038ddfe38cc9fe6310573>.
> A historical first draft is preserved as a gist at
> <https://gist.github.com/potiuk/43aa334087cf1fdb2908662e592a192a>
> for reference; this in-repo document is the canonical version.
> Last revised 2026-05-30.

**Provenance legend** — every claim is tagged:
- *(documented)* — verbatim or paraphrased from a project public
  artefact (cited inline).
- *(maintainer)* — confirmed by an APISIX PMC member.
- *(inferred)* — synthesis from public artefacts; the PMC has
  not yet confirmed. Every *(inferred)* claim also appears in
  §4.14 as an Open Question. (None remain in the current
  revision.)

**Confidence**: ~70 *(documented)* / 28 *(maintainer)* / 0
*(inferred)*. All §4.14 open questions have been resolved with
the PMC; q-21 (dashboard admin-key storage) was resolved by
reducing scan scope (see §4.11a, §4.14 q-21).

---

## §4.1 Header

- **Project**: Apache APISIX (gateway), apisix-ingress-controller.
  (apache/apisix-dashboard is out of current scan scope per PMC
  decision 2026-05-26; see §4.11a.)
- **Model version**: 2026-05-30 (revised), against `apache/apisix@main`
  and `apache/apisix-ingress-controller@main` at the date above.
- **Scope**: apache/apisix + apache/apisix-ingress-controller
  (apache/apisix-dashboard out of current scan scope per PMC
  2026-05-26).
- **Stewardship**: this document is maintainer-stewarded by the
  Apache APISIX PMC.
- **Historical reference**: a first-draft version of this
  document is preserved at
  <https://gist.github.com/potiuk/43aa334087cf1fdb2908662e592a192a>
  for traceability of the §4.14 promotion pass.
- **Version binding**: this model describes APISIX as of the
  commits listed above. A report against an earlier release (e.g.,
  3.x) is triaged against the model as it stood for that release;
  if a security property was added later, the earlier release is
  not in scope. *(maintainer — confirmed by Ming Wen 2026-05-15)*
- **Reporting cross-reference**: findings that fall under §4.8 (claimed
  properties) should be reported privately per the project's
  disclosure policy (security@apache.org). Findings that fall under
  §4.3 or §4.9 will be closed with a pointer to this document.
- **Status**: **maintainer-confirmed; revised 2026-05-30.**

**One-paragraph description.** Apache APISIX is a dynamic,
cloud-native API gateway built on OpenResty (nginx + LuaJIT).
A single APISIX deployment terminates HTTP/HTTPS/gRPC/TCP/UDP
client traffic, applies route-matched plugin logic (auth, rate
limiting, transformation, observability), and forwards to upstream
services. Configuration is held in etcd (or in YAML in
standalone mode) and mutated through the **Admin API**. The
**apisix-ingress-controller** translates Kubernetes Ingress /
Gateway-API resources into Admin API calls. (The
**apisix-dashboard** — a React SPA that does the same on behalf
of a human operator — is part of the broader APISIX project but
is out of the current scan scope; see §4.11a.)

---

## §4.2 Scope and intended use

**Intended deployments** *(documented — README, deployment-modes.md)*:
- **Edge gateway** — single APISIX cluster in front of upstream
  services, performing routing, auth, rate limiting, transformation.
- **Service mesh sidecar / ingress controller** — APISIX as a
  Kubernetes Ingress / Gateway-API implementation via
  apisix-ingress-controller.
- **Decoupled control-plane / data-plane deployments** — separate
  APISIX instances configured for `role: data_plane` and
  `role: control_plane`.
- **Standalone mode** — file-backed config (no etcd), suited to
  immutable infrastructure / GitOps. *(documented —
  deployment-modes.md)*

**Caller roles.** A gateway has more than one "caller":

| Role | Trust level | Typical channel |
|---|---|---|
| **External client** | untrusted | HTTPS / HTTP / TCP / UDP traffic to data-plane port (default 9080). |
| **Operator / admin** | trusted | Admin API (default 9180) or Kubernetes CRDs via the ingress controller. |
| **Upstream service** | operator-trusted | HTTP / HTTPS / gRPC to backend; operator chose to put it behind APISIX. |
| **etcd peer** | operator-trusted | gRPC to etcd (TLS optional). |
| **Plugin runner subprocess** *(external plugins)* | operator-trusted | Unix-socket RPC; subprocess inherits APISIX user. *(documented — external-plugin.md)* |
| **Operator-supplied Lua / serverless code** | operator-trusted | embedded in route config; executes inside the worker. *(documented — plugin-develop.md, serverless-pre-function plugin)* |

**Component-family table.**

| Family | Representative entry point | Process-external side effects | In/out of model |
|---|---|---|---|
| Gateway data-plane (Lua, OpenResty) | `POST /any-route` on `node_listen` | network egress to upstream, log sinks, etcd reads | **in** |
| Gateway control-plane (Admin API) | `PUT /apisix/admin/routes/<id>` on `admin_listen` | etcd writes, plugin reloads | **in** |
| etcd watch + reload | `apisix/core/config_etcd.lua` | etcd reads, in-process state mutation | **in** |
| Plugin host (Lua) | each route's `plugins:` config | filesystem / network access available to any plugin | **in** |
| External plugin runner | unix socket RPC | subprocess, runs as APISIX uid | **in** *(documented — external-plugin.md)* |
| Stream proxy (raw TCP/UDP) | `stream_proxy` listener | upstream TCP / UDP | **in** |
| Ingress controller | Kubernetes CRD watcher → Admin API | K8s API, etcd writes via APISIX | **in** |
| `bin/`, `t/`, `example/`, `ci/`, `.github/`, demo configs | n/a | n/a | **out** *(maintainer — confirmed by Ming Wen 2026-05-15)* |
| Vendored Lua runtime dependencies under `deps/` and `lua_modules/` | varies | varies | **in** (per apisix-master-0.rockspec runtime deps) *(maintainer — confirmed by Ming Wen 2026-05-15)* |
| Test fixtures under `t/lib/` | varies | varies | **out** *(maintainer — confirmed by Ming Wen 2026-05-15)* |

---

## §4.3 Out of scope (explicit non-goals)

The following are not threat-model scope. A report whose root
cause sits here is closed as `OUT-OF-MODEL` with a pointer to the
specific bullet below.

1. **Operator misconfiguration** that voids a documented default-secure
   posture. Examples: exposing the Admin API on `0.0.0.0` without
   changing `admin_listen.allow_admin` from its default
   `127.0.0.0/24`; running with the documented-as-known
   default Admin API key `edd1c9f034335f136f87ad84b625c8f1`
   (the `conf/config.yaml` warning calls this out explicitly).
   *(documented — admin-api.md, conf/config.yaml:59-63)*
2. **etcd security as such.** APISIX assumes etcd is operator-secured
   (TLS, auth, network isolation). A finding that requires
   compromising etcd is not an APISIX finding.
   *(maintainer — confirmed by Ming Wen 2026-05-15)*
3. **Upstream service vulnerabilities.** APISIX routes traffic to
   operator-chosen upstreams; bugs *in those upstreams* are out of
   scope. *(maintainer — confirmed by Ming Wen 2026-05-15)*
4. **Operator-supplied Lua code** (custom plugins via
   `extra_lua_path`, `serverless-pre-function` /
   `serverless-post-function` route-embedded code, custom external
   plugin runners). This code is loaded into the same worker
   process with full `ngx.*` access — by design *(documented —
   plugin-develop.md, external-plugin.md)*. The PMC is responsible
   for the Apache-maintained plugins under `apisix/plugins/`; the
   operator is responsible for their own. Exception: the example
   snippets in `docs/` are PMC responsibility — an exploitable
   documented example is a documentation bug, triaged as
   `VALID-HARDENING`. *(maintainer — confirmed by Ming Wen 2026-05-15)*
5. **All plugins are opt-in; none are active without explicit
   per-route configuration.** A plugin is only on the request hot
   path once an operator names it in a route's `plugins:` block (or
   in an `ApisixPluginConfig` / `ApisixRoute` CRD). There is no
   "default-enabled plugins subset". Enabling a plugin and finding
   a bug in it is in scope of §4.8 for any plugin shipped under
   `apisix/plugins/`. *(maintainer — confirmed by Ming Wen 2026-05-15)*
6. **Kubernetes cluster security** — RBAC, namespace isolation,
   network policy, admission controllers. The ingress controller
   assumes the cluster operator has gated who can create
   `ApisixRoute` / `ApisixConsumer` / `ApisixPluginConfig`
   resources (documented duty: creators of `ApisixRoute` must be
   the namespace owner or equivalent trust tier). The
   controller's own RBAC requirements are documented in
   `apisix-ingress-controller/config/rbac/role.yaml`.
   *(maintainer — confirmed by Ming Wen 2026-05-15)*
7. **Browser-host compromise.** A browser-extension stealing the
   admin key from an operator's browser is not in scope.
   *(maintainer — confirmed by Ming Wen 2026-05-15)*
8. **Side-channel attacks** (timing, cache, electromagnetic).
   APISIX is a Lua/Go application; constant-time crypto at the
   TLS layer is the responsibility of the underlying TLS stack
   (OpenSSL via OpenResty / Go's `crypto/tls`). APISIX's own
   credential comparisons (admin key, JWT secret, HMAC signature,
   etc.) are expected to be constant-time — that is a §4.8
   property, not a §4.3 exclusion. *(maintainer — confirmed by
   Ming Wen 2026-05-15)*
9. **Denial-of-service via resource exhaustion** of layers below
   APISIX (kernel TCP backlog, file descriptor limit, host RAM).
   APISIX provides rate-limiting / circuit-breaker plugins but
   does not enforce them by default. *(maintainer — confirmed by
   Ming Wen 2026-05-15; see §4.10)*
10. **Code in `bin/`, `t/`, `example/`, `benchmark/`, `ci/`,
    `.github/`** — test fixtures, smoke scripts, benchmark
    harnesses, CI configuration. Not deployed to production.
    `t/lib/` test fixtures are likewise out of model. *(maintainer
    — confirmed by Ming Wen 2026-05-15)*

---

## §4.4 Trust boundaries and data flow

**Primary trust boundaries** (where untrusted data crosses into
the trusted core):

```
                                            (operator)
                                                |
                                                v
External client --HTTPS-->  [data-plane     <--+
(untrusted)                  worker process    |
                             — Lua plugins,    | Admin API
                             route table,      | (X-API-KEY)
                             upstream pool]    |
                                ^      |       |
                                |      |       |
                            (etcd      |       |
                             config    |   [Admin
                             reads)    |    handler]
                                |      v       |
                              etcd <---+---> etcd writes
                              (operator-secured, TLS optional)
                                                ^
                                                |
                                (apisix-ingress-controller,
                                 curl / human operator)
```

*(documented — architecture-design/apisix.md, admin-api.md,
deployment-modes.md)*

**Boundary transitions:**

1. **External-client → worker.** OpenResty / nginx parses the
   HTTP message; APISIX Lua plugins then run with the parsed
   request and may inspect / rewrite / reject. Trust transition:
   bytes go from "untrusted network input" to "parsed Lua table
   passed to plugin code". The parser is the foundational
   defence; plugins after it work with already-parsed inputs.
2. **Admin API → worker.** Admin API requires `X-API-KEY`. After
   auth, the JSON body is validated against the resource's JSON
   Schema before being written to etcd. Trust transition:
   "authenticated operator input" → "schema-validated config".
3. **etcd → worker.** Workers subscribe to etcd watches and
   apply config changes. Trust transition: none in principle
   — etcd content was already operator-authored or
   Admin-API-mediated.
4. **Ingress controller → Admin API.** The controller reads
   Kubernetes CRDs, translates to Admin API calls signed with
   `X-API-KEY` (configured via a Kubernetes Secret). Trust
   transition: "Kubernetes-authorized CRD" → "Admin API call".

**Reachability preconditions per family** (the test a triager
applies to a finding before anything else):

| Family | A finding here is in-model only if reachable from… |
|---|---|
| Data-plane Lua plugins | a client request on `node_listen` that matches a route that has the plugin enabled. |
| Admin API handlers | an authenticated Admin API call from a caller inside `allow_admin`. |
| etcd watch handler | an etcd write whose key is under `prefix` (default `/apisix`). |
| Stream proxy | a TCP/UDP packet on `stream_proxy.*_listen`. |
| Ingress controller | a CRD a Kubernetes RBAC-authorized user created in a watched namespace. |
| External-plugin runner | the gateway worker is calling the runner via unix socket. |

---

## §4.5 Assumptions about the environment

- **Operating system / runtime**: Linux is the only supported
  production deployment target. macOS is dev/test only.
  Windows / BSD / Solaris and other non-Linux platforms are
  out of model; a report against a non-Linux deployment is
  closed as `OUT-OF-MODEL: unsupported-platform`.
  *(maintainer — confirmed by Ming Wen 2026-05-15)*
- **Runtime**: OpenResty (nginx + LuaJIT). Plugin code runs as
  Lua coroutines inside nginx workers. *(documented —
  architecture-design/apisix.md)*
- **Concurrency**: nginx multi-worker; per-worker Lua state.
  Plugins must not assume single-worker state. *(documented —
  plugin-develop.md notes shared-dict and `core.table.new` patterns)*
- **Time / clock**: relies on the host clock for cache TTLs and
  rate-limit windows. Clock-drift behaviour (JWT replay-window
  edge cases, rate-limit window roll-over) is **out of model**;
  NTP synchronization is an operator responsibility (see §4.10).
  *(maintainer — confirmed by Ming Wen 2026-05-15)*
- **Network**: data-plane port reachable by clients; Admin API
  port restricted to operator network; etcd reachable from
  workers; outbound from workers to upstreams + log sinks
  (Kafka, Datadog, etc.). *(documented — admin-api.md,
  ssl-protocol.md)*
- **Filesystem**: APISIX reads `conf/config.yaml` and any files
  named under `extra_lua_path`. SSL cert/key material can be
  stored on filesystem **or** in etcd; etcd-stored keys are
  plaintext-in-etcd by default unless etcd encryption-at-rest is
  configured by the operator, or `apisix.data_encryption` is
  enabled for field-level encryption. *(documented —
  apisix/core/etcd.lua; see §4.8 point 11)*

**Negative claims — what APISIX does *not* do to its host:**
*(maintainer — confirmed by Ming Wen 2026-05-15; all 5 hold as
written.)*
- Does not require root after startup (drops to non-root worker user).
- Does not install global signal handlers beyond what nginx itself does.
- Does not fork persistent daemon subprocesses beyond
  configured external-plugin runners.
- Does not write outside `logs/` and the OpenResty / etcd cache
  directories.
- Does not phone home or call any vendor endpoint.

---

## §4.5a Build-time and configuration variants

The following config knobs change which §4.8 properties hold.
*(All *(documented)* unless tagged otherwise.)*

| Knob | Default | Effect when flipped from default | Maintainer stance |
|---|---|---|---|
| `deployment.admin.admin_key[].key` | `edd1c9f0…` (in docs / sample config) | Without changing it, the Admin API has no real auth. | **Documented as required to change in production.** A report against an unchanged default is `OUT-OF-MODEL: operator-misconfig` per §4.3. *(maintainer — confirmed by Ming Wen 2026-05-15)* |
| `deployment.admin.allow_admin` | `127.0.0.0/24` | Widening to `0.0.0.0/0` exposes Admin API to the network. | `OUT-OF-MODEL: operator-misconfig` if widened and then exploited. *(maintainer — confirmed by Ming Wen 2026-05-15)* |
| `deployment.admin.enable_admin` | `true` | `false` disables the Admin API; the data plane reads etcd directly (decoupled mode). | Both supported. Decoupled mode is recommended for internet-facing / public-edge deployments; traditional mode is appropriate for internal-network deployments. *(maintainer — confirmed by Ming Wen 2026-05-15)* |
| `deployment.etcd.tls.{cert,key,verify}` | unset (plaintext) | Enabling TLS protects etcd traffic. | **Required if etcd is networked** (multi-host or cross-zone). Optional for single-host loopback deployments. *(maintainer — confirmed by Ming Wen 2026-05-15)* |
| `apisix.ssl.listen` / `ssl_protocols` | TLS 1.2 / 1.3, no 1.0/1.1 | Re-enabling 1.0/1.1 weakens transport. | Documented; not recommended. *(documented — ssl-protocol.md)* |
| `plugins:` list | (no enabled plugins; all opt-in) | Naming a plugin on a route enables it. | All plugins are opt-in; a CVE on any Apache-maintained plugin under `apisix/plugins/` is CVE-equivalent regardless of how widely it tends to be enabled in the wild. *(maintainer — confirmed by Ming Wen 2026-05-15)* |
| `extra_lua_path` | unset | Loading operator-supplied Lua plugins. Those are out of model per §4.3 point 4. | *(documented — plugin-develop.md)* |
| `apisix.role` | `traditional` | `data_plane` / `control_plane` change which surface is exposed. | Documented; security implications laid out in deployment-modes.md. *(documented)* |
| `apisix.data_encryption` | unset / disabled | Enables field-level encryption of sensitive consumer-credential fields in etcd. | Optional in 3.x; not enabled by default. See §4.8 point 11. *(maintainer — confirmed by Ming Wen 2026-05-15)* |

**The insecure-default case** (per the rubric): the Admin API
ships with a documented-as-known weak key. The `conf/config.yaml`
sample explicitly says *"using fixed API token has security
risk, please update it when you deploy to production
environment."* Reading **(b)** is confirmed: the default is a
dev-convenience and operators are documented as required to flip
it. A report that exploits the unchanged default key is
`OUT-OF-MODEL: operator-misconfig`. *(maintainer — confirmed by
Ming Wen 2026-05-15)*

---

## §4.6 Assumptions about inputs

**Per-component input table** (grouped by family from §4.2).

### Gateway data-plane

| Endpoint / message | Field | Attacker-controllable? | Caller / operator must enforce |
|---|---|---|---|
| Any route on `node_listen` | request line (method, URI, query) | **yes** | route regex must not be catastrophic backtracking (project applies an Anti-ReDoS policy on input regex). *(documented — admin API validation)* |
| Any route | request headers (incl. `X-Forwarded-*`) | **yes** | not to be trusted as authentication ground truth unless an `ip-restriction` / `real-ip` plugin is on. *(documented — real-ip plugin doc)* |
| Any route | request body | **yes** | size bounded by `client_max_body_size`; content trusted only insofar as the route's plugins validated it. |
| `stream_proxy` | TCP / UDP payload | **yes** | upstream is responsible for protocol handling; APISIX forwards bytes. |
| TLS handshake | SNI | **yes** | SNI is used for cert selection but **not** treated as authenticated identity. *(documented — ssl-protocol.md)* |

### Gateway control-plane (Admin API)

| Endpoint | Field | Attacker-controllable? | Caller must enforce |
|---|---|---|---|
| `PUT /apisix/admin/routes/<id>` | `plugins.{*}.{*}` | **yes if Admin API exposed** | JSON-Schema validated before persist; schema must reject unsafe shapes. *(documented — plugin schema validation)* |
| `PUT /apisix/admin/ssls/<id>` | `cert`, `key` | trusted (operator) | private key is stored in etcd; etcd security is the protective layer (see §4.8 point 11 for optional `apisix.data_encryption`). |
| `PUT /apisix/admin/consumers/<id>` | `username`, plugin creds | trusted (operator) | Stored in etcd under `/apisix/consumers/<username>`, organized per plugin (key-auth: `key`; jwt-auth: `key`+`secret`+`algorithm`; basic-auth: `username`+`password`; hmac-auth: `access_key`+`secret_key`; etc.). Optional field-level encryption via `apisix.data_encryption`. *(maintainer — confirmed by Ming Wen 2026-05-15)* |
| `POST /apisix/admin/routes` | `script` (legacy) | trusted (operator) | **arbitrary Lua execution by design** — same trust posture as `extra_lua_path`. The `script` field is currently still present and is planned for removal in the next release; semantically equivalent to `extra_lua_path` (out-of-model per §4.3 point 4). *(maintainer — confirmed by Ming Wen 2026-05-15)* |

### Ingress controller

| Surface | Field | Attacker-controllable? | Cluster operator must enforce |
|---|---|---|---|
| `ApisixRoute.spec.http[*].plugins[*]` | plugin config | depends on RBAC | restrict CRD creation to trusted namespaces / users; creators of `ApisixRoute` must be the namespace owner or equivalent trust tier. *(maintainer — confirmed by Ming Wen 2026-05-15)* |
| `ApisixConsumer.spec.plugins[*]` | credential material | depends on RBAC | same as above. |
| `ApisixPluginConfig` | shared plugin block | depends on RBAC | same. |

**Size, shape, rate assumptions.** Request size bounded by
`client_max_body_size` (nginx-level; default 8KB but the project
ships 1m). Connection rate bounded by kernel + worker_connections.
Rate-limiting and circuit-breaker plugins are **opt-in** — APISIX
does not rate-limit by default. *(documented — limit-req,
limit-count, limit-concurrency plugin docs)*

---

## §4.7 Adversary model

**Adversaries in scope.**

1. **External untrusted client** — a remote network attacker
   speaking HTTP / HTTPS / TCP / UDP / gRPC to `node_listen`.
   They can send arbitrary, malformed, or oversized requests.
   They aim to: bypass route auth; reach an upstream they
   shouldn't; crash a worker; cause CPU / memory exhaustion;
   read configured-secret material (e.g., an Authorization
   header that another plugin sets).
2. **Authenticated client** — a client with valid credentials
   for **one** route or consumer, attempting to reach a route
   or consumer they should not have access to (horizontal
   privilege escalation through auth-plugin bugs).
3. **Compromised plugin author** — limited to plugins shipped
   in `apisix/plugins/`, since that's the trust boundary the
   PMC owns. All Apache-maintained plugin bugs are CVE-equivalent;
   since all plugins are opt-in (§4.3 point 5), there is no
   priority differentiation between "default-loaded" and
   "opt-in". Operator-supplied plugins are out per §4.3 point 4.
   *(maintainer — confirmed by Ming Wen 2026-05-15)*
4. **Unprivileged Kubernetes user** with create rights on
   `ApisixRoute` in some namespace, attempting to influence
   traffic outside that namespace via the ingress controller.
   The cluster operator's documented duty is to gate CRD
   creation appropriately (§4.3 point 6). *(maintainer —
   confirmed by Ming Wen 2026-05-15)*

**Adversaries out of scope** (cross-ref §4.3):
- Operator with Admin API credentials. They've already won.
- Operator-supplied Lua code authors.
- An attacker who has compromised etcd.
- An attacker who has compromised the host running APISIX.
- An attacker with physical access / hypervisor access /
  co-tenant capabilities on the same VM.
- A compromised log-sink endpoint. Log sinks are operator-trusted
  infrastructure. (Sink-failure-availability and
  malicious-sink-response resilience is a §4.8 property — see
  point 10 — not an adversary in this section.) *(maintainer —
  confirmed by Ming Wen 2026-05-15)*

---

## §4.8 Security properties the project provides

For each property: the property, violation symptom, severity
tier, provenance.

1. **HTTP request parsing safety.**
   - Property: malformed HTTP requests on `node_listen` cause
     `400` rejection, not worker memory corruption or RCE.
     HTTP/1.1 / HTTP/2 wire-level parsing bugs are owned by
     upstream nginx (APISIX tracks and ships fixed versions);
     APISIX's own Lua-phase parsing (custom header / query /
     body handling, gRPC metadata, etc.) is APISIX-owned.
   - Violation symptom: worker segfault / OOB read / RCE
     triggered by request bytes.
   - Severity: **security-critical (CVE).**
   - Provenance: *(documented — relies on nginx's parser; project
     does not duplicate parsing)*; *(maintainer — confirmed by
     Ming Wen 2026-05-15: layered ownership)*.

2. **Admin API authentication gate.**
   - Property: any Admin API call without a valid
     `X-API-KEY` (matching `admin_key[].key`) returns 401 and
     does not mutate state.
   - Violation symptom: an unauthenticated request modifies a
     route or reads a consumer secret.
   - Severity: **security-critical (CVE).**
   - Provenance: *(documented — admin-api.md, t/admin/api.t)*.

3. **Admin API IP allowlist.**
   - Property: a request from outside
     `deployment.admin.allow_admin` is rejected at network level
     (returns 403 or connection refused).
   - Violation symptom: Admin API reachable from disallowed CIDR.
   - Severity: security-critical (CVE) if bypassed; operator
     misconfiguration if widened intentionally.
   - Provenance: *(documented — config.yaml comments)*.

4. **JSON-Schema validation of plugin configs.**
   - Property: the Admin API rejects plugin configs that fail
     the plugin's published JSON Schema; only schema-conformant
     configs are written to etcd.
   - Violation symptom: a config that violates the schema is
     accepted, then crashes the worker at apply time.
   - Severity: high (denial-of-service via crash); CVE if it
     escalates to RCE.
   - Provenance: *(documented — plugin.lua schema-validation
     path)*.

5. **TLS termination.**
   - Property: APISIX terminates TLS using configured ciphersuites
     in line with `ssl_protocols`; TLS 1.0 / 1.1 disabled by
     default.
   - Violation symptom: SSL/TLS downgrade or cert mis-selection
     under SNI.
   - Severity: high (CVE for cipher / protocol bypass).
   - Provenance: *(documented — ssl-protocol.md)*.

6. **Plugin chain authorization.**
   - Property: each plugin runs in the configured phase order;
     a plugin cannot suppress later auth plugins from running
     unless documented to (e.g., `serverless-pre-function`,
     which is by design able to rewrite, short-circuit, or
     bypass later auth plugins — operators enabling it take on
     responsibility for the resulting trust model, concrete
     instance of §4.3 point 4).
   - Violation symptom: a plugin's misordering causes an
     unauthenticated request to reach the upstream.
   - Severity: security-critical (CVE).
   - Provenance: *(documented — plugin.lua phase chain)*;
     *(maintainer — confirmed by Ming Wen 2026-05-15:
     `serverless-*` interactions are by design)*.

7. **Rate-limit / circuit-break plugin integrity.**
   - Property: when `limit-req` / `limit-count` /
     `limit-concurrency` are configured, their counters are
     consulted on the request hot path and exceeding the limit
     yields `503` / `429` (per config).
   - Violation symptom: a counter is bypassed; an attacker
     achieves > N requests per window despite a configured limit.
   - Severity: high (DoS) or critical (depending on what the
     limit gated).
   - Provenance: *(documented — limit-req.md, limit-count.md)*.

8. **Ingress-controller fidelity.**
   - Property: every field accepted by an `apisix.apache.org`
     CRD spec maps to a defined Admin API target. Silent drop,
     injection, or renaming is an `apisix-ingress-controller`
     bug — not operator misconfiguration. An e2e contract test
     enforcing this invariant is recommended.
   - Violation symptom: controller injects fields the CRD did
     not request; or controller silently drops a field that
     was required for security.
   - Severity: security-critical if a drop voids an auth-plugin
     configuration.
   - Provenance: *(maintainer — confirmed by Ming Wen 2026-05-15)*.

9. **Constant-time comparison of credentials.**
   - Property: APISIX's own credential comparisons — admin key,
     JWT secret, HMAC signature, and equivalent secrets stored
     by auth plugins — use constant-time comparison so that
     remote timing cannot be used to recover the secret. (TLS-
     layer side channels remain out of model and are delegated
     to OpenSSL / Go `crypto/tls`.)
   - Violation symptom: a measurable timing oracle on `X-API-KEY`,
     JWT verification, HMAC verification, etc.
   - Severity: high (credential disclosure).
   - Provenance: *(maintainer — confirmed by Ming Wen 2026-05-15;
     §4.14 q-5)*.

10. **Log-sink failure / malicious-response resilience.**
    - Property: a slow, failed, or actively malicious log-sink
      endpoint (Kafka / Datadog / Splunk / HTTP logger) must
      not impact APISIX availability — no worker hang, no RCE,
      no segfault triggered by sink-side bytes.
    - Violation symptom: a worker hangs / crashes / executes
      attacker-controlled code as a result of bytes returned by
      a log-sink endpoint.
    - Severity: high (DoS) or critical (RCE).
    - Provenance: *(maintainer — confirmed by Ming Wen 2026-05-15;
      §4.14 q-17)*.

11. **Optional field-level encryption of sensitive consumer
    fields (`apisix.data_encryption`).**
    - Property: when `apisix.data_encryption` is enabled (3.x;
      not enabled by default), sensitive fields in consumer /
      ssl resources are encrypted before being written to etcd.
    - Violation symptom: with the knob enabled, the protected
      field is still readable in plaintext in etcd.
    - Severity: high (credential disclosure if etcd is observed).
    - Provenance: *(maintainer — confirmed by Ming Wen 2026-05-15;
      §4.14 q-14)*.

<!-- §4.8 point 9 (former "Dashboard does not persist the admin key") removed
in the 2026-05-30 revision because apisix-dashboard is out of current scan
scope (PMC decision 2026-05-26; see §4.11a and §4.14 q-21). Re-add this
property as a §4.8 line when dashboard re-enters scope. -->

---

## §4.9 Security properties the project does NOT provide

1. **Default-strong Admin API key** — APISIX ships a documented
   weak default; operators must rotate. *(documented — see §4.5a)*
2. **etcd-side encryption / authentication by default** —
   etcd ships unauth and plaintext; operator's responsibility.
   *(maintainer — confirmed by Ming Wen 2026-05-15)*
3. **CSRF protection on the Admin API.** The Admin API uses
   `X-API-KEY`-header auth, not session cookies; CSRF as
   typically understood is not the threat. But: a malicious
   page loaded in the operator's browser cannot directly read
   Admin API responses (same-origin) unless the operator has
   widened CORS — APISIX does not set permissive CORS by
   default. *(maintainer — confirmed by Ming Wen 2026-05-15)*
4. **Plugin sandboxing** — Lua plugins run in the same worker
   process with full `ngx.*` access; external-plugin runners
   inherit the APISIX uid. A compromised in-tree plugin is RCE
   in the gateway. *(documented — plugin-develop.md,
   external-plugin.md)*
5. **RBAC on the Admin API.** The Admin API has a single global
   admin role; there is no fine-grained read-only vs write
   distinction, no per-resource ACL. *(documented — admin-api.md)*
6. **Audit log of Admin API changes.** APISIX itself does not
   emit a structured audit log of Admin API mutations; operators
   wire one externally (access-log on the Admin API listener
   combined with `kafka-logger` / `http-logger` to a SIEM —
   see §4.10). *(maintainer — confirmed by Ming Wen 2026-05-15)*
7. **Rate-limit on the Admin API.** The data-plane rate-limit
   plugins do not protect the Admin API; operator must front
   the Admin API with firewall / WAF / fail2ban (see §4.10).
   *(maintainer — confirmed by Ming Wen 2026-05-15)*
8. **Prevention of operator-supplied plugin RCE.** By design;
   see §4.3 point 4.

---

## §4.10 Downstream responsibilities

What the operator must do to inherit the §4.8 properties:

1. **Change the Admin API key** from the documented default,
   and store it outside `config.yaml` (env var, K8s Secret,
   external secret manager). *(documented)*
2. **Restrict `allow_admin`** to operator workstations or
   bastions; do not widen to `0.0.0.0/0`. *(documented)*
3. **Run etcd with TLS + auth** if etcd is on a network reachable
   by anything other than the APISIX worker — required when
   networked (multi-host or cross-zone); optional for
   single-host loopback. Configure
   `deployment.etcd.tls.{cert,key,verify}` accordingly.
   *(maintainer — confirmed by Ming Wen 2026-05-15)*
4. **Audit operator-supplied plugins** (`extra_lua_path`,
   serverless-pre/post, external plugin runners) before deploy
   — this code is in the trusted-by-design tier. *(documented)*
5. **Configure rate-limiting + circuit-breaker plugins** for
   any production-facing route; APISIX does not impose these by
   default. *(documented)*
6. **Use decoupled mode** (separate `data_plane` / `control_plane`
   roles, or `standalone` mode) for any internet-facing /
   public-edge deployment; this removes the Admin API from the
   data-plane's blast radius. Traditional mode remains
   appropriate for internal-network deployments. *(maintainer
   — confirmed by Ming Wen 2026-05-15)*
7. **Restrict Kubernetes RBAC** so that only trusted
   service-accounts / users can create `ApisixRoute` /
   `ApisixConsumer` / `ApisixPluginConfig` CRDs. Documented
   duty: creators of `ApisixRoute` must be the namespace
   owner or equivalent trust tier. *(maintainer — confirmed
   by Ming Wen 2026-05-15)*
8. **Choose TLS configuration consciously**: at minimum the
   defaults (TLS 1.2 / 1.3); enable mTLS for client-cert auth
   where required. *(documented)*
9. **Synchronize the host clock (NTP).** Clock-drift behaviour
   of JWT replay windows and rate-limit window roll-over is
   not an APISIX security violation — operator must keep host
   time in sync. *(maintainer — confirmed by Ming Wen 2026-05-15;
   §4.14 q-8)*
10. **Wire Admin-API audit logging externally.** APISIX does not
    emit a structured admin-mutation audit log; operators
    combine access-log on the Admin API listener with
    `kafka-logger` / `http-logger` to a SIEM. *(maintainer —
    confirmed by Ming Wen 2026-05-15; §4.14 q-22)*
11. **Front the Admin API with firewall / WAF / fail2ban.**
    Data-plane rate-limit plugins do not protect the Admin API
    — operator must add a rate-limit / brute-force defence
    layer in front of it. *(maintainer — confirmed by Ming Wen
    2026-05-15; §4.14 q-23)*
12. **Strip the `Server: APISIX/x.y.z` banner if banner-grabbing
    is a concern.** Use the `response-rewrite` plugin or a
    custom `error_page` directive. (Version disclosure via
    default error page is itself a `KNOWN-NON-FINDING` — see
    §4.11a — but operators who want to harden against it have
    a documented path.) *(maintainer — confirmed by Ming Wen
    2026-05-15; §4.14 q-27)*

---

## §4.11 Known misuse patterns

Each is a pattern the PMC has seen often enough to warrant a
heads-up. *(maintainer — confirmed by Ming Wen 2026-05-15: all
7 below match PMC experience.)*

1. Running with the documented-as-weak Admin API key in
   production. (The doc literally warns against it; reports here
   are not findings.)
2. Putting the Admin API on `0.0.0.0` with the default
   `allow_admin` widened to `0.0.0.0/0`.
3. Running etcd unauthenticated and reachable from anything
   other than the worker host.
4. Loading operator-supplied Lua via `extra_lua_path` or
   `serverless-pre-function` without an internal review.
5. Treating `X-Forwarded-For` / `X-Real-IP` as authenticated
   identity without the `real-ip` plugin or the equivalent
   upstream-PROXY-protocol handling.
6. Storing SSL private keys in etcd without etcd encryption-at-rest
   or TLS (and without enabling `apisix.data_encryption`).
7. Single shared admin key across multiple operators (no
   per-operator key, no audit trail).

---

## §4.11a Known non-findings (recurring false positives)

*(maintainer — confirmed by Ming Wen 2026-05-15: all 8 below are
consistent with the PMC's historical security-report archive.)*

1. **Hardcoded default Admin API key in `conf/config.yaml`** —
   intentional dev-convenience; flagged in the same file's
   comment. Reports: `OUT-OF-MODEL: operator-misconfig`.
2. **`X-API-KEY`-style header auth on the Admin API** — the
   project's auth scheme by design. Reports asking "why not
   OAuth?" are `OUT-OF-MODEL: by-design`.
3. **Operator-supplied Lua executes in the worker** — by design,
   see §4.3 point 4.
4. **etcd plaintext-by-default** — operator-responsibility per
   §4.10 point 3.
5. **Plugin runs in same process as gateway core** — by design
   per §4.9 point 4.
6. **No CSRF tokens on Admin API** — the Admin API uses header
   auth, not cookie auth; not CSRF-applicable in the usual sense.
   (See §4.9 point 3 for nuance.)
7. **Version disclosure** in default error pages / responses
   — common ASF stance; operators harden via custom error
   pages or `response-rewrite` (see §4.10 point 12).
   *(maintainer — confirmed by Ming Wen 2026-05-15: confirmed
   `KNOWN-NON-FINDING`.)*
8. **OUT-OF-SCOPE: `apache/apisix-dashboard`.** The dashboard
   is excluded from the current scan run per the PMC's
   2026-05-26 message. Findings against the dashboard repo
   are not part of this model. The previously-tracked
   localStorage admin-key persistence finding (q-21) is being
   addressed in a separate PR against `apache/apisix-dashboard`
   (`atomWithStorage` → `atom` change). When the dashboard
   re-enters scan scope, §4.8 will regain its "dashboard does
   not persist the admin key" property.

---

## §4.12 Conditions that would change this model

- New deployment role (e.g., a future `gateway_dashboard_unified`
  mode where the dashboard is served by APISIX itself).
- New auth plugin that grants partial Admin API access (would
  require revisiting §4.9 point 5).
- Dropping or strengthening the Anti-ReDoS policy on route
  regexes.
- A new external-plugin protocol that drops the same-uid
  assumption.
- Re-inclusion of `apache/apisix-dashboard` in scan scope (would
  restore the dashboard-related §4.8 property and the
  dashboard-specific §4.2 / §4.6 rows).

---

## §4.13 Triage dispositions

A report against any of the in-scope repos is closed under one
of these labels. *(maintainer — confirmed by Ming Wen 2026-05-15:
the 9 dispositions below are sufficient; no additions or removals.)*

| Disposition | When | Body of reply |
|---|---|---|
| `VALID` | violates a §4.8 property; reachable per §4.4. | Acknowledged; coordinated disclosure timeline; fix planned for release. |
| `VALID-HARDENING` | not a §4.8 violation but tightens a §4.9 property in a way the PMC accepts (includes exploitable `docs/` example snippets). | Acknowledged; lower priority; may merge as hardening PR. |
| `OUT-OF-MODEL: operator-misconfig` | the issue is an instance of §4.3 point 1 or §4.11 (operator widened a default, did not rotate the admin key, ran etcd unauth, etc.). | Cite the relevant §4.5a / §4.10 row. |
| `OUT-OF-MODEL: trusted-input` | report supplies attacker-controlled bytes through a parameter the §4.6 table marks "not attacker-controllable" (e.g., a `format` literal, a plugin's `script` field — note that the `script` example is valid until the next-release removal lands, per §4.14 q-15). | Cite the §4.6 row. |
| `OUT-OF-MODEL: adversary-not-in-scope` | the threat requires capabilities the §4.7 adversary doesn't have (operator credentials, etcd compromise, host compromise, side-channel, compromised log sink). | Cite the §4.7 adversary list. |
| `OUT-OF-MODEL: out-of-tree-code` | finding is in operator-supplied Lua / external-plugin code / a vendored library that is itself out of model. | Cite §4.3 point 4 or §4.2 component-family table. |
| `OUT-OF-MODEL: unsupported-platform` | report is against a non-Linux deployment (macOS dev/test, Windows, BSD, etc.). | Cite §4.5 OS row. |
| `BY-DESIGN: property-disclaimed` | finding hits an explicit §4.9 non-property (no plugin sandbox, no RBAC, etc.). | Cite the §4.9 line. |
| `KNOWN-NON-FINDING` | exact match to a §4.11a entry. | Cite §4.11a line; one-paragraph reply. |
| `MODEL-GAP` | the report describes a real bug, but this document does not have a §4.8 property covering it. | The PMC will decide whether to add a §4.8 line (turning into `VALID`) or a §4.9 line (turning into `BY-DESIGN`). |

<!-- The unsupported-platform row was promoted to a first-class disposition
during the §4.14 q-7 confirmation pass (2026-05-15). -->

---

## §4.14 Open Questions for the Maintainers — RESOLVED

All 28 open questions raised in the 2026-05-15 draft were answered
by the PMC (Ming Wen, 2026-05-15). The corresponding *(inferred)*
tags in the body have been promoted to *(maintainer — confirmed
by Ming Wen 2026-05-15)*. The answer summaries are kept below for
traceability.

1. **(§4.2 vendored libs)** `deps/` and `lua_modules/` are
   in-model — APISIX runtime dependencies per
   `apisix-master-0.rockspec`. `t/lib/` is out-of-model (test
   fixtures).
2. **(§4.3 point 4 / `docs/`)** Operator-supplied Lua is out-of-
   model. Exception: `docs/` example snippets are PMC
   responsibility — an exploitable documented example is a
   documentation bug triaged as `VALID-HARDENING`.
3. **(§4.5a plugins list)** All plugins are disabled by default.
   No plugin processes traffic without explicit operator
   configuration on a route. The "default-enabled subset"
   framing has been removed everywhere.
4. **(K8s RBAC)** Controller's own RBAC requirements are
   documented in
   `apisix-ingress-controller/config/rbac/role.yaml`. Cluster
   operator's duty: creators of `ApisixRoute` must be the
   namespace owner or equivalent trust tier.
5. **(Side channels)** TLS-layer side channels are out-of-model
   (delegated to OpenSSL / Go `crypto/tls`). APISIX's own
   credential comparisons must be constant-time — added as
   §4.8 point 9.
6. **(`bin/`, `t/`, etc.)** `ci/` and `.github/` added to the
   out-of-model directory list (§4.3 point 10).
7. **(OS)** Linux is the only supported production target.
   macOS is dev/test only. A report against a non-Linux
   deployment is closed as `OUT-OF-MODEL: unsupported-platform`
   (§4.13).
8. **(Clock drift)** Out-of-model. NTP sync is an operator
   responsibility (§4.10 point 9). JWT replay-window edge
   cases and rate-limit window roll-over are not APISIX
   security violations.
9. **(Negative claims)** All 5 negative claims hold as written.
10. **(`allow_admin` widening)** `OUT-OF-MODEL:
    operator-misconfig`. Same rationale as the default admin
    key.
11. **(Deployment modes)** Both modes supported. Decoupled
    mode recommended for internet-facing deployments;
    traditional mode appropriate for internal-network
    deployments.
12. **(etcd TLS)** Required when etcd is networked
    (`deployment.etcd.tls.{cert,key,verify}`). Optional for
    single-host loopback. Added to §4.10 point 3.
13. **(Admin-key default)** Reading **(b)** confirmed:
    `OUT-OF-MODEL: operator-misconfig`. See §4.5a.
14. **(Consumer credentials)** Stored in etcd under
    `/apisix/consumers/<username>`, per-plugin. Optional
    `apisix.data_encryption` for field-level encryption in 3.x
    (not enabled by default). Added as §4.8 point 11.
15. **(`script` field)** Currently present on
    `apisix/admin/routes`; planned for removal in the next
    release. Semantically equivalent to `extra_lua_path` (out-
    of-model per §4.3 point 4). The §4.13 `OUT-OF-MODEL:
    trusted-input` example using `script` stays until the
    next-release removal lands.
16. **(Plugin author trust)** All Apache-maintained plugin
    bugs are CVE-equivalent. No "default-loaded" vs "opt-in"
    distinction — since all plugins are opt-in (q-3), the
    distinction does not apply.
17. **(Log sinks)** Operator-trusted; "compromised log-sink
    endpoint" removed from §4.7 adversary list. Sink-failure-
    availability resilience added as §4.8 point 10.
18. **(Parser bugs)** Layered: HTTP/1.1 + HTTP/2 wire-level
    bugs → upstream nginx; APISIX's own Lua-phase parsing →
    APISIX-owned. Folded into §4.8 point 1.
19. **(`serverless-*` interactions)** By-design.
    `serverless-pre-function` can rewrite / short-circuit /
    bypass later auth plugins; concrete instance of §4.3
    point 4. Folded into §4.8 point 6.
20. **(Controller fidelity)** §4.8 commitment. Every CRD spec
    field maps to a defined Admin API target; silent drop /
    injection / rename is a controller bug. E2e contract test
    recommended. Folded into §4.8 point 8.
21. **(Dashboard key storage)**
    `KNOWN-NON-FINDING-for-current-scope`: dashboard is OUT
    OF SCAN SCOPE per PMC decision 2026-05-26; the
    localStorage admin-key persistence finding is tracked in
    a separate PR against `apache/apisix-dashboard`
    (`atomWithStorage` → `atom` change). Re-add the
    in-memory-only property to §4.8 only when dashboard
    re-enters scope. See §4.11a point 8.
22. **(Audit log)** Out-of-model; operator-wired (§4.10 point
    10). Folded into §4.9 point 6.
23. **(Admin-API rate-limit)** Out-of-model; operator-fronted
    (§4.10 point 11). Folded into §4.9 point 7.
24. **(Dashboard multi-tenant)** Out-of-scope. The dashboard
    is a single-admin-key, fully-privileged tool; multi-
    operator / audited use requires external SSO + Admin API
    RBAC (RBAC not provided — §4.9 point 5). With the
    dashboard out of current scan scope (§4.11a point 8),
    this question is dormant for the current scan run.
25. **(Misuse patterns)** All 7 listed misuse patterns match
    PMC experience. No additions.
26. **(Known non-findings)** All originally-listed non-
    findings are consistent with PMC's historical archive.
    Entry 8 (dashboard out-of-scope) added in this revision.
27. **(Version disclosure)** Confirmed `KNOWN-NON-FINDING`.
    Operator hardening via `response-rewrite` / `error_page`
    added to §4.10 point 12.
28. **(Triage dispositions)** The 9 dispositions are
    sufficient. The `unsupported-platform` row was promoted
    to a first-class entry on the same pass (per q-7).

---

*Revision 2026-05-30 — all originally-inferred claims resolved;
scope reduced to `apache/apisix` + `apache/apisix-ingress-controller`
per PMC 2026-05-26 decision (apisix-dashboard tracked separately).*
