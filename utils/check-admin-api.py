#!/usr/bin/env python3
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
"""Offline checks for the release's Admin API OpenAPI document.

Validation-only dependencies: jsonschema, openapi-spec-validator, lupa.
Install them in a virtual environment, then run python utils/check-admin-api.py.
No server, credentials, or external documentation repository is used.
Lua 5.1 evaluates schema_def.lua, which has no requires or runtime side effects.
This checks static schema parity; it does not replace live Admin API tests.
"""

import copy
import json
import re
from pathlib import Path

from jsonschema import Draft202012Validator
from lupa import LuaRuntime
from openapi_spec_validator import validate
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

if not __debug__:
    raise RuntimeError("run this checker without Python optimization so validation assertions remain active")

ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / "docs/en/latest/admin-api.json"


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        assert key not in result, f"Duplicate JSON key: {key}"
        result[key] = value
    return result


spec_text = SPEC.read_text()
assert not re.search(r"api7|apiseven", spec_text, re.IGNORECASE)
spec = json.loads(spec_text, object_pairs_hook=unique_object)
assert not re.search(r"-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----", spec_text)


def walk(value, location=""):
    yield location, value
    if isinstance(value, dict):
        for key, child in value.items():
            yield from walk(child, location + "/" + key)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from walk(child, location + "/" + str(index))


def deref(value):
    while isinstance(value, dict) and "$ref" in value:
        pointer = value["$ref"]
        assert pointer.startswith("#/"), f"External reference: {pointer}"
        value = spec
        for segment in pointer[2:].split("/"):
            value = value[segment.replace("~1", "/").replace("~0", "~")]
    return value


refs = 0
for location, value in walk(spec):
    if isinstance(value, dict) and "$ref" in value:
        deref(value)
        refs += 1
validate(spec)
version = re.search(r'VERSION = "([^"]+)"',
                    (ROOT / "apisix/core/version.lua").read_text()).group(1)
assert spec["info"]["version"] == version
assert spec["x-apisix-source"]["version"] == version

# Use an in-memory registry: no HTTP retrieval during example validation.
uri = "urn:apisix:admin-api"
registry = Registry().with_resource(
    uri, Resource.from_contents(spec, default_specification=DRAFT202012))
resolver = registry.resolver(uri)
counts = {"examples": 0, "defaults": 0, "schemas": 0}


def check_example(schema, example, location):
    validator = Draft202012Validator(schema, registry=registry, _resolver=resolver)
    errors = list(validator.iter_errors(example))
    assert not errors, f"{location}: " + "; ".join(e.message for e in errors)
    counts["examples"] += 1


def check_schema(schema, location):
    Draft202012Validator.check_schema(schema)
    counts["schemas"] += 1
    # Descend only into schemas, not example data or named property containers.
    for keyword, value in schema.items():
        if keyword in ("properties", "patternProperties", "$defs", "dependentSchemas"):
            for name, child in value.items():
                check_schema(child, location + "/" + keyword + "/" + name)
        elif keyword in ("allOf", "anyOf", "oneOf", "prefixItems"):
            for index, child in enumerate(value):
                check_schema(child, location + "/" + keyword + "/" + str(index))
        elif keyword in ("items", "additionalProperties", "not", "if", "then", "else", "contains"):
            if isinstance(value, dict):
                check_schema(value, location + "/" + keyword)
    if "default" in schema:
        check_example(schema, schema["default"], location + "/default")
        counts["defaults"] += 1
    for index, example in enumerate(schema.get("examples", [])):
        check_example(schema, example, location + "/examples/" + str(index))


for name, schema in spec["components"]["schemas"].items():
    check_schema(schema, "components/schemas/" + name)


def check_media(content, location):
    for mime, item in content.items():
        schema = item.get("schema", {})
        check_schema(schema, location + "/" + mime)
        if "example" in item:
            check_example(schema, item["example"], location)
        for name, example in item.get("examples", {}).items():
            example = deref(example)
            assert "externalValue" not in example
            check_example(schema, example["value"], location + "/" + name)


operations = set()
ids = set()
for path, item in spec["paths"].items():
    for method, op in item.items():
        if method == "parameters":
            continue
        operations.add((path.removeprefix("/apisix/admin"), method))
        assert re.fullmatch(r"[A-Za-z][A-Za-z0-9]*", op["operationId"])
        assert op["operationId"] not in ids, op["operationId"]
        ids.add(op["operationId"])
        params = [deref(p) for p in item.get("parameters", []) + op.get("parameters", [])]
        keys = [(p["in"], p["name"]) for p in params]
        assert len(keys) == len(set(keys)), (path, method, "duplicate parameters")
        expected = set(re.findall(r"{([^}]+)}", path))
        actual = {p["name"] for p in params if p["in"] == "path"}
        assert expected == actual, (path, method, expected, actual)
        for param in params:
            assert param["in"] != "path" or param["required"]
            check_schema(param["schema"], path + "/" + param["name"])
            if "example" in param:
                check_example(param["schema"], param["example"], path)
        if "requestBody" in op:
            check_media(deref(op["requestBody"])["content"], path + "/" + method + "/request")
        assert op["responses"], (path, method)
        for status, response in op["responses"].items():
            response = deref(response)
            assert response["description"]
            assert method != "head" or "content" not in response
            check_media(response.get("content", {}), path + "/" + method + "/" + status)

# Independently derive supported CRUD methods from each release module.
modules = {
    "routes": "routes", "services": "services", "upstreams": "upstreams",
    "consumers": "consumers", "ssls": "ssl", "global_rules": "global_rules",
    "consumer_groups": "consumer_group", "plugin_configs": "plugin_config",
    "stream_routes": "stream_routes", "protos": "proto",
    "plugin_metadata": "plugin_metadata", "secrets": "secrets",
}
expected_ops = set()
for resource, module in modules.items():
    text = (ROOT / f"apisix/admin/{module}.lua").read_text()
    match = re.search(r"unsupported_methods\s*=\s*{([^}]+)}", text)
    unsupported = set(re.findall(r'"(\w+)"', match.group(1))) if match else set()
    base = "/" + resource
    suffix = "/{username}" if resource == "consumers" else "/{plugin_name}" if resource == "plugin_metadata" else "/{secret_type}/{id}" if resource == "secrets" else "/{id}"
    item = base + suffix
    expected_ops.update([(base, "get"), (item, "get"), (item, "put"), (item, "delete")])
    if resource not in ("secrets", "plugin_metadata"):
        expected_ops.add((base, "put"))
    if "post" not in unsupported:
        expected_ops.add((base, "post"))
    if "patch" not in unsupported:
        expected_ops.update([(item, "patch"), (item + "/{sub_path}", "patch")])
expected_ops.add(("/secrets/{secret_type}", "get"))
expected_ops.update({
    ("/consumers/{username}/credentials", "get"),
    ("/consumers/{username}/credentials", "put"),
    ("/consumers/{username}/credentials/{id}", "get"),
    ("/consumers/{username}/credentials/{id}", "put"),
    ("/consumers/{username}/credentials/{id}", "delete"),
    ("/plugins/{plugin_name}", "get"), ("/schema/plugins/{plugin_name}", "get"),
    ("/plugins", "get"), ("/plugins/list", "get"), ("/plugins/reload", "put"),
    ("/schema/{resource}", "get"), ("/schema/validate/{resource}", "post"),
    ("", "head"), ("/configs", "get"), ("/configs", "put"),
    ("/configs", "head"), ("/configs/validate", "post"),
})
assert operations == expected_ops, ("Missing", expected_ops - operations, "Extra", operations - expected_ops)

# Evaluate the exact release schema_def.lua with Lua 5.1. Normalize only the
# Draft 4 dependencies keyword into the equivalent 2020-12 keywords.
def native_json(value, key=""):
    if hasattr(value, "items"):
        keys = list(value.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [native_json(value[i]) for i in range(1, len(keys) + 1)]
        if not keys and key in {"required", "enum", "allOf", "anyOf", "oneOf", "examples", "default"}:
            return []
        result = {str(k): native_json(v, str(k)) for k, v in value.items()}
        dependencies = result.pop("dependencies", {})
        for name, dependency in dependencies.items():
            keyword = "dependentRequired" if isinstance(dependency, list) else "dependentSchemas"
            result.setdefault(keyword, {})[name] = dependency
        return result
    return value


def expand(value):
    if isinstance(value, dict):
        if "$ref" in value:
            return expand(deref(value))
        return {key: expand(child) for key, child in value.items()}
    if isinstance(value, list):
        return [expand(child) for child in value]
    return value


native = native_json(LuaRuntime().execute((ROOT / "apisix/schema_def.lua").read_text()))
parity = 0
for name, schema in spec["components"]["schemas"].items():
    if "x-apisix-schema" not in schema:
        continue
    exported = copy.deepcopy(schema)
    key = exported.pop("x-apisix-schema")
    exported.pop("description", None)
    original = copy.deepcopy(native[key])
    original.pop("description", None)
    assert expand(exported) == original, f"Native schema drift: {name}"
    parity += 1

# The three built-in secret manager schemas are local declarations. Evaluate
# only those declarations with uri_def, without importing networking modules.
lua = LuaRuntime()
lua_source = lua.execute((ROOT / "apisix/schema_def.lua").read_text())
for backend in ("vault", "aws", "gcp"):
    text = (ROOT / f"apisix/secret/{backend}.lua").read_text()
    declaration = text[text.index("local schema = {"):text.index("\nlocal _M =")]
    value = lua.execute("local core = {schema = ...}\n" + declaration + "\nreturn schema", lua_source)
    assert native_json(value) == expand(spec["components"]["schemas"][backend.title() + "Secret"])

# Ensure the request variants remove only timestamps and the injected id
# requirement, while retaining every release constraint on actual fields.
for name, schema in spec["components"]["schemas"].items():
    if "x-apisix-schema" not in schema:
        continue
    expected_request = expand(schema)
    expected_request.pop("x-apisix-schema")
    expected_request.pop("description", None)
    for field in ("create_time", "update_time"):
        expected_request["properties"].pop(field, None)
        if "upstream" in expected_request["properties"]:
            expected_request["properties"]["upstream"]["properties"].pop(field, None)
    if "required" in expected_request:
        required = [v for v in expected_request["required"] if v != "id"]
        if required:
            expected_request["required"] = required
        else:
            expected_request.pop("required")
    actual_request = expand(spec["components"]["schemas"][name + "Request"])
    actual_request.pop("description", None)
    assert actual_request == expected_request, f"Request schema drift: {name}"

print(f"PASS: OpenAPI {spec['openapi']}; APISIX {version}; {len(operations)} operations; "
      f"{refs} internal refs; unique operation IDs and exact path parameters")
print(f"PASS: {parity} native resource/request schemas and 3 secret manager schemas; {counts['schemas']} schema checks; "
      f"{counts['examples']} example/default validations; {counts['defaults']} defaults")
