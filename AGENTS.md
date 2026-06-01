<!--
  Licensed to the Apache Software Foundation (ASF) under one
  or more contributor license agreements.  See the NOTICE file
  distributed with this work for additional information
  regarding copyright ownership.  The ASF licenses this file
  to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance
  with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing,
  software distributed under the License is distributed on an
  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
  KIND, either express or implied.  See the License for the
  specific language governing permissions and limitations
  under the License.
-->

# Apache APISIX — Agent Instructions

This file is read by automated agents (security scanners, code
analyzers, AI assistants) operating on this repository. It
points them at the human-authored references they should
consult before producing output.

## Security Model

The authoritative security threat model for Apache APISIX is
at [`docs/en/latest/security-threat-model.md`](docs/en/latest/security-threat-model.md).

Agents producing security-relevant analysis against this
repository should consult that document first — in particular
the §4.3 (out of scope), §4.9 (properties NOT provided),
§4.11a (known non-findings), and §4.13 (triage dispositions)
sections, which govern whether a given finding is in-scope
for Apache APISIX itself or out-of-scope (operator
misconfiguration, downstream concern, etc.).
