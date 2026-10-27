#!/usr/bin/env python3
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements. See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Offline Admin OpenAPI structural, example, and release-source parity checks.

Requires lupa, jsonschema and openapi-spec-validator. Run from the repository root.
Lua schema tables are evaluated without loading APISIX, Nginx or external modules.
This is static verification; runtime check_schema callbacks still apply.
"""
import copy
import hashlib
import json
import re
from pathlib import Path

from lupa.lua51 import LuaRuntime, lua_type
from openapi_spec_validator import validate
from jsonschema import Draft202012Validator
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

if not __debug__:
    raise RuntimeError("run this checker without Python optimization so validation assertions remain active")

SPEC = Path('docs/en/latest/admin-api.json')
MAPPING = {
    'Route': 'route', 'Service': 'service', 'Upstream': 'upstream',
    'Consumer': 'consumer', 'Credential': 'credential', 'SSL': 'ssl',
    'GlobalRule': 'global_rule', 'StreamRoute': 'stream_route',
    'ConsumerGroup': 'consumer_group', 'PluginConfig': 'plugin_config',
    'Proto': 'proto', 'ResourceId': 'id_schema',
}


def no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        assert key not in result, f'duplicate JSON key: {key}'
        result[key] = value
    return result


def convert(value, key=''):
    if lua_type(value) != 'table':
        return value
    keys = list(value.keys())
    if keys and all(isinstance(k, int) for k in keys):
        return [convert(value[i]) for i in range(1, len(keys) + 1)]
    if not keys and key in {'required', 'enum', 'oneOf', 'anyOf', 'allOf'}:
        return []
    return {k: convert(v, k) for k, v in value.items()}


def normalize(value):
    """Convert draft-04 dependencies/bounds to JSON Schema 2020-12."""
    if isinstance(value, list):
        return [normalize(v) for v in value]
    if not isinstance(value, dict):
        return value
    result = {k: normalize(v) for k, v in value.items()}
    for key, val in result.pop('dependencies', {}).items():
        keyword = 'dependentRequired' if isinstance(val, list) else 'dependentSchemas'
        result.setdefault(keyword, {})[key] = val
    for exclusive, bound in [('exclusiveMinimum', 'minimum'),
                             ('exclusiveMaximum', 'maximum')]:
        if isinstance(result.get(exclusive), bool):
            if result.pop(exclusive):
                result[exclusive] = result.pop(bound)
    return result


def main():
    spec_text = SPEC.read_text()
    assert not re.search(r'api7|apiseven', spec_text, re.IGNORECASE)
    spec = json.loads(spec_text, object_pairs_hook=no_duplicates)
    validate(spec)
    assert spec['openapi'] == '3.1.0'
    version = re.search(r'VERSION\s*=\s*"([^"]+)"',
                        Path('apisix/core/version.lua').read_text()).group(1)
    assert spec['info']['version'] == version == '3.17.0'
    assert spec['x-apisix-source']['branch'] == 'release/3.17'
    # Reject all external $refs: validation never downloads a schema.
    counters = dict(refs=0, schemas=0, examples=0, defaults=0, operations=0)
    uri = 'urn:apisix:admin-openapi'
    resource = Resource.from_contents(spec, default_specification=DRAFT202012)
    registry = Registry().with_resource(uri, resource)

    def resolve(obj):
        while isinstance(obj, dict) and '$ref' in obj:
            counters['refs'] += 1
            assert obj['$ref'].startswith('#/'), obj['$ref']
            target = spec
            for part in obj['$ref'][2:].split('/'):
                target = target[part.replace('~1', '/').replace('~0', '~')]
            obj = target
        return obj

    def check(value, schema, location, kind):
        counters[kind] += 1
        # Local references in a subschema refer to the complete OpenAPI document.
        def absolute_refs(obj):
            if isinstance(obj, list):
                return [absolute_refs(x) for x in obj]
            if not isinstance(obj, dict):
                return obj
            return {k: uri + v if k == '$ref' and v.startswith('#')
                    else absolute_refs(v) for k, v in obj.items()}
        validator = Draft202012Validator(absolute_refs(schema), registry=registry)
        errors = list(validator.iter_errors(value))
        assert not errors, f'{location}: {errors[0].message}'

    def walk(obj, location=''):
        if isinstance(obj, list):
            for i, value in enumerate(obj):
                walk(value, f'{location}/{i}')
        if not isinstance(obj, dict):
            return
        resolve(obj)
        if 'schema' in obj:
            schema = resolve(obj['schema'])
            counters['schemas'] += 1
            if 'example' in obj:
                check(obj['example'], schema, location, 'examples')
            for example in obj.get('examples', {}).values():
                example = resolve(example)
                if 'value' in example:
                    check(example['value'], schema, location, 'examples')
        if 'type' in obj or any(k in obj for k in ('anyOf', 'oneOf', 'allOf')):
            if 'default' in obj:
                check(obj['default'], obj, location, 'defaults')
            if isinstance(obj.get('examples'), list):
                for value in obj['examples']:
                    check(value, obj, location, 'examples')
        for key, value in obj.items():
            walk(value, location + '/' + key)

    walk(spec)
    ids = set()
    for path, item in spec['paths'].items():
        for method, operation in item.items():
            if method not in {'get', 'put', 'post', 'patch', 'delete', 'head'}:
                continue
            counters['operations'] += 1
            opid = operation['operationId']
            assert re.fullmatch('[A-Za-z][A-Za-z0-9]*', opid), opid
            assert opid not in ids, opid
            ids.add(opid)
            parameters = [resolve(p) for p in item.get('parameters', [])
                          + operation.get('parameters', [])]
            assert len({(p['in'], p['name']) for p in parameters}) == len(parameters)
            path_params = [p for p in parameters if p['in'] == 'path']
            assert {p['name'] for p in path_params} == set(re.findall(r'{([^}]+)}', path))
            assert all(p.get('required') for p in path_params)

    annotations = {'description', 'title', 'examples', 'example', 'readOnly', 'writeOnly'}

    def constraints(obj):
        if isinstance(obj, list):
            return [constraints(x) for x in obj]
        if not isinstance(obj, dict):
            return obj
        obj = resolve(obj)
        return {k: constraints(v) for k, v in obj.items() if k not in annotations}

    lua = LuaRuntime(unpack_returned_tuples=True)
    source = normalize(convert(lua.execute(Path('apisix/schema_def.lua').read_text())))
    schemas = spec['components']['schemas']
    for schema in schemas.values():
        Draft202012Validator.check_schema(schema)
    for name, key in MAPPING.items():
        assert constraints(schemas[name]) == constraints(source[key]), name
    for name, key in MAPPING.items():
        if name == 'ResourceId':
            continue
        expected = copy.deepcopy(source[key])
        for field in ('create_time', 'update_time'):
            expected['properties'].pop(field, None)
            if 'upstream' in expected['properties']:
                expected['properties']['upstream']['properties'].pop(field, None)
        if 'required' in expected:
            expected['required'] = [x for x in expected['required'] if x != 'id']
            if not expected['required']:
                expected.pop('required')
        assert constraints(schemas[name + 'Input']) == constraints(expected), name + 'Input'
    expected = copy.deepcopy(source['ssl'])
    for field in ('key', 'keys'):
        expected['properties'].pop(field)
    for branch in expected['then']['oneOf'] + [expected['else']]:
        branch['required'] = [x for x in branch['required'] if x != 'key']
    assert constraints(schemas['SSLRead']) == constraints(expected), 'SSLRead'
    for backend, name in [('vault', 'VaultSecret'), ('aws', 'AwsSecret'),
                          ('gcp', 'GcpSecret')]:
        text = Path(f'apisix/secret/{backend}.lua').read_text()
        table = text[text.index('local schema ='):text.index('local _M =')]
        core = lua.table_from({'schema': lua.table_from({
            'uri_def': lua.table_from(source['uri_def'])})})
        actual = normalize(convert(lua.execute('local core = ...; ' + table
                                               + '; return schema', core)))
        assert constraints(schemas[name]) == constraints(actual), name

    # Handler surface: derive resource names, exclusions, collection POST and item methods.
    init = Path('apisix/admin/init.lua').read_text()
    block = init[init.index('local resources ='):init.index('local _M =')]
    resources = dict(re.findall(r'(\w+)\s*=\s*require\("apisix.admin.([\w_]+)"\)', block))
    for resource_name, module in resources.items():
        if resource_name in {'schema', 'plugins'}:
            continue
        text = Path(f'apisix/admin/{module}.lua').read_text()
        match = re.search(r'unsupported_methods\s*=\s*{([^}]+)}', text)
        unsupported = set(re.findall(r'"(\w+)"', match.group(1))) if match else set()
        base = '/apisix/admin/' + resource_name
        if resource_name == 'credentials':
            base = '/apisix/admin/consumers/{username}/credentials'
        if resource_name == 'secrets':
            base += '/{secret_type}'
        key = 'username' if resource_name == 'consumers' else (
            'plugin_name' if resource_name == 'plugin_metadata' else 'id')
        expected = {'get', 'put', 'patch', 'delete'} - unsupported
        actual = set(spec['paths'][base + '/{' + key + '}'])
        assert expected <= actual, (resource_name, expected - actual)
        assert not (actual & unsupported), resource_name
        if 'post' not in unsupported:
            assert 'post' in spec['paths'][base], resource_name
    # Hand-audited dispatch/response logic is frozen by local file hashes. An implementation
    # change requires renewed semantic review, not silently updating a generated spec.
    manifest = json.loads(Path('utils/admin-api-openapi-sources.json').read_text())
    for filename, digest in manifest.items():
        assert hashlib.sha256(Path(filename).read_bytes()).hexdigest() == digest, filename
    print('PASS: JSON, OpenAPI 3.1, local refs, operation IDs, path parameters,')
    print('      examples/defaults, version, 12 core + 3 secret schemas, handler methods,')
    print(f'      and {len(manifest)} reviewed source hashes')
    print(json.dumps(counters, sort_keys=True))
    print('Spec SHA256:', hashlib.sha256(SPEC.read_bytes()).hexdigest())


if __name__ == '__main__':
    main()
