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

# Admin API OpenAPI Source

This directory contains the modular source for the Admin API OpenAPI
document.

- `openapi.json` defines document metadata and references each path and
  component module.
- `paths/` contains one OpenAPI Path Item per file.
- `components/` contains one reusable OpenAPI component per file, grouped
  by component type.

Edit these source files rather than
`docs/en/latest/admin-api.json`. Generate the self-contained document after
making a change:

```shell
make bundle-admin-api-spec
```

The command uses a pinned Redocly CLI version, resolves all external
references, and writes deterministic, formatted JSON to
`docs/en/latest/admin-api.json`. CI runs the same command and fails when the
committed bundle is stale.

Generating the bundle requires Node.js 22.12.0 or later and npm. The script
invokes `@redocly/cli@2.72.1` explicitly so local and CI generation use the
same bundler version.

References inside a module are relative to that module. For example, a path
module can reference a schema with
`../components/schemas/Route.json`, while one schema can reference another
schema in the same directory with `./ResourceId.json`.
