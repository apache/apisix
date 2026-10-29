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

"""Validate the checked-in Admin API contract; never download contract inputs."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import re
import shlex
import sys
from urllib.parse import unquote, urlsplit

from jsonschema import Draft202012Validator
from jsonschema.exceptions import SchemaError
from openapi_spec_validator import OpenAPIV31SpecValidator
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

ROOT = Path(__file__).resolve().parents[1]
METHODS = {'get', 'put', 'post', 'delete', 'patch', 'head', 'options', 'trace'}
BASE = 'urn:apisix:admin-api'
# These contain instance data, not contract objects or schemas.
DATA = {'example', 'default', 'enum', 'const', 'value'}
MAPS = {'properties', 'patternProperties', '$defs', 'dependentSchemas', 'schemas',
        'paths', 'responses', 'content', 'headers', 'links', 'callbacks', 'pathItems',
        'requestBodies', 'parameters', 'securitySchemes', 'examples'}


def objects(value, path='#', mapping=False):
    """Walk contract objects, keeping arbitrary names and instance data separate."""
    if isinstance(value, dict):
        if not mapping:
            yield path, value
        for key, child in value.items():
            if mapping or (key not in DATA and not key.startswith('x-')):
                if not mapping and key == 'examples' and isinstance(child, list):
                    continue  # JSON Schema examples are instance data.
                yield from objects(child, path + '/' + key.replace('~', '~0').replace('/', '~1'),
                                   not mapping and key in MAPS and isinstance(child, dict))
    elif isinstance(value, list):
        for i, child in enumerate(value):
            yield from objects(child, path + '/' + str(i))


def resolve(document, ref):
    if not isinstance(ref, str) or not ref.startswith('#/'):
        raise ValueError(f'only internal JSON Pointer refs are allowed: {ref!r}')
    result = document
    for token in unquote(ref[2:]).split('/'):
        token = token.replace('~1', '/').replace('~0', '~')
        try:
            result = result[int(token)] if isinstance(result, list) else result[token]
        except (KeyError, IndexError, ValueError, TypeError) as exc:
            raise ValueError(f'unresolved ref: {ref}') from exc
    return result


def dereference(document, obj):
    seen = set()
    while isinstance(obj, dict) and '$ref' in obj:
        ref = obj['$ref']
        if ref in seen:
            raise ValueError(f'cyclic Reference Object: {ref}')
        seen.add(ref)
        obj = resolve(document, ref)
    return obj


def absolute_refs(value):
    result = deepcopy(value)
    for _, obj in objects(result):
        for key in ('$ref', '$dynamicRef'):
            if key in obj:
                obj[key] = BASE + obj[key]
    return result


def validate(document, versions):
    """Return actionable errors. Local ref preflight runs before the OAS library."""
    errors = []
    if document.get('openapi') != '3.1.0':
        errors.append('openapi must be 3.1.0')
    version = document.get('info', {}).get('version')
    for source, expected in versions.items():
        if version != expected:
            errors.append(f'info.version {version!r} differs from {source}: {expected!r}')
    for path, obj in objects(document):
        for key in ('$ref', '$dynamicRef'):
            if key in obj:
                try:
                    resolve(document, obj[key])
                except ValueError as exc:
                    errors.append(f'{path}: {exc}')
        if '$id' in obj:
            errors.append(f'{path}: embedded $id changes local ref scope; use document pointers')
    if errors:
        return errors

    schemas = list(document.get('components', {}).get('schemas', {}).items())
    schemas += [(path + '/schema', obj['schema']) for path, obj in objects(document)
                if 'schema' in obj]
    for path, schema in schemas:
        try:
            Draft202012Validator.check_schema(schema)
        except SchemaError as exc:
            errors.append(f'{path}: invalid JSON Schema: {exc.message}')
    if errors:
        return errors
    errors.extend('OpenAPI: ' + str(e) for e in OpenAPIV31SpecValidator(document).iter_errors())
    if errors:
        return errors
    registry = Registry().with_resource(
        BASE, Resource.from_contents(absolute_refs(document), default_specification=DRAFT202012))

    def check_value(schema, value, location):
        validator = Draft202012Validator(absolute_refs(schema), registry=registry)
        errors.extend(f'{location}: {e.message}' for e in validator.iter_errors(value))

    def check_schema(schema, location):
        for path, obj in objects(schema, location):
            if 'default' in obj:
                check_value(obj, obj['default'], path + '/default')
            if 'examples' in obj:
                for i, example in enumerate(obj['examples']):
                    check_value(obj, example, path + f'/examples/{i}')
            if 'example' in obj:
                check_value(obj, obj['example'], path + '/example')

    # Components plus schemas on parameters, request bodies, response media and headers.
    for name, schema in document.get('components', {}).get('schemas', {}).items():
        check_schema(schema, '#/components/schemas/' + name)
    for path, obj in objects(document):
        if 'schema' not in obj:
            continue
        schema = obj['schema']
        check_schema(schema, path + '/schema')
        if 'example' in obj:
            check_value(schema, obj['example'], path + '/example')
        for name, example in obj.get('examples', {}).items():
            example = dereference(document, example)
            if 'externalValue' in example:
                errors.append(f'{path}/examples/{name}: use a checked-in value, not externalValue')
            elif 'value' in example:
                check_value(schema, example['value'], path + '/examples/' + name)

    ids = set()
    for path, raw_item in document.get('paths', {}).items():
        item = dereference(document, raw_item)
        for method in METHODS & item.keys():
            op = item[method]
            location = f'{method.upper()} {path}'
            if not op.get('responses'):
                errors.append(f'{location}: responses must be non-empty')
            op_id = op.get('operationId')
            if not isinstance(op_id, str) or not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*', op_id) or op_id in ids:
                errors.append(f'{location}: missing or duplicate operationId {op_id!r}')
            ids.add(op_id)
            params = {}
            for group in (item.get('parameters', []), op.get('parameters', [])):
                for param in group:
                    param = dereference(document, param)
                    params[(param['in'], param['name'])] = param
            declared = {name for (where, name) in params if where == 'path'}
            if declared != set(re.findall(r'{([^{}]+)}', path)):
                errors.append(f'{location}: path parameters do not match template')
            for (where, name), param in params.items():
                if where == 'path' and param.get('required') is not True:
                    errors.append(f'{location}: path parameter {name} must be required')
            for field in ('requestBody', 'responses'):
                entries = op.get('responses', {}).values() if field == 'responses' else [op.get(field)]
                for entry in entries:
                    if entry is None:
                        continue
                    entry = dereference(document, entry)
                    for media, content in entry.get('content', {}).items():
                        if 'schema' not in content:
                            errors.append(f'{location} {field} {media}: missing schema')

            for sample in op.get('x-codeSamples', []):
                if sample.get('lang', '').lower() != 'curl':
                    continue
                try:
                    args = shlex.split(sample['source'])
                    url = next(x for x in args if x.startswith(('http://', 'https://')))
                    expected_path = re.sub(r'{[^}]+}', r'[^/]+', path)
                    if not re.fullmatch(expected_path, urlsplit(url).path):
                        errors.append(f'{location}: cURL URL does not match operation')
                    actual_method = args[args.index('-X') + 1].lower() if '-X' in args else 'get'
                    if actual_method != method:
                        errors.append(f'{location}: cURL method does not match operation')
                    for flag in ('-d', '--data', '--data-raw'):
                        if flag in args:
                            body = json.loads(args[args.index(flag) + 1])
                            schema = dereference(document, op['requestBody'])['content']['application/json']['schema']
                            check_value(schema, body, location + '/curl')
                except (ValueError, KeyError, StopIteration) as exc:
                    errors.append(f'{location}: invalid cURL sample: {exc}')
    return errors


def repository_versions(root):
    versions = {f'docs/{lang}/latest/config.json': json.loads(
        (root / f'docs/{lang}/latest/config.json').read_text())['version'] for lang in ('en', 'zh')}
    text = (root / 'apisix/core/version.lua').read_text()
    versions['apisix/core/version.lua'] = re.search(r'VERSION\s*=\s*"([^"]+)"', text).group(1)
    return versions


def validate_source(document, root):
    """Compare structural constraints with this checkout's pure Lua schema table.

    Lupa evaluates schema_def.lua only: no APISIX module or network is loaded.
    This is not an OpenResty integration test or a replacement for Lua checkers.
    """
    from lupa import LuaRuntime, lua_type

    def from_lua(value):
        if lua_type(value) != 'table':
            return value
        keys = list(value.keys())
        if keys and all(isinstance(key, int) for key in keys):
            return [from_lua(value[i]) for i in range(1, len(keys) + 1)]
        result = {key: from_lua(value[key]) for key in keys}
        if 'dependencies' in result:
            dependencies = result.pop('dependencies')
            for keyword, typ in [('dependentSchemas', dict), ('dependentRequired', list)]:
                entries = {k: v for k, v in dependencies.items() if isinstance(v, typ)}
                if entries:
                    result[keyword] = entries
        return result

    lua = LuaRuntime()
    lua_schema = lua.execute((root / 'apisix/schema_def.lua').read_text())
    source = from_lua(lua_schema)

    def constraints(value):
        if isinstance(value, list):
            return [constraints(item) for item in value]
        if not isinstance(value, dict):
            return value
        if '$ref' in value:
            return constraints(resolve(document, value['$ref']))
        return {k: constraints(v) for k, v in value.items()
                if k not in {'description', 'title', 'readOnly', 'examples', 'example'}
                and not k.startswith('x-')}

    names = {'ResourceId': 'id_schema', 'Route': 'route', 'Service': 'service',
             'Upstream': 'upstream', 'Consumer': 'consumer', 'Credential': 'credential',
             'ConsumerGroup': 'consumer_group', 'GlobalRule': 'global_rule',
             'PluginConfig': 'plugin_config', 'SSL': 'ssl', 'StreamRoute': 'stream_route',
             'Proto': 'proto', 'GraphQLCostDecoration': 'graphql_cost_decoration'}
    errors = []
    schemas = document['components']['schemas']
    for name, key in names.items():
        expected = constraints(source[key])
        # resource.check_conf injects the path id before running these schemas.
        if name in {'ConsumerGroup', 'GlobalRule', 'PluginConfig'}:
            expected['required'].remove('id')
        if constraints(schemas[name]) != expected:
            errors.append(f'{name}: structural constraints differ from schema_def.lua ({key})')

    lua.globals().core = lua.table_from({'schema': lua_schema})
    for name, backend in [('VaultSecret', 'vault'), ('AwsSecret', 'aws'), ('GcpSecret', 'gcp')]:
        text = (root / f'apisix/secret/{backend}.lua').read_text()
        declaration = 'local schema =' + text.split('local schema =', 1)[1].split('local _M', 1)[0]
        expected = from_lua(lua.execute(declaration + '\nreturn schema'))
        if constraints(schemas[name]) != constraints(expected):
            errors.append(f'{name}: structural constraints differ from secret/{backend}.lua')

    # Check supported canonical CRUD methods against resource.new declarations.
    modules = {'routes': 'routes', 'services': 'services', 'upstreams': 'upstreams',
               'consumers': 'consumers', 'ssls': 'ssl', 'global_rules': 'global_rules',
               'consumer_groups': 'consumer_group', 'plugin_configs': 'plugin_config',
               'plugin_metadata': 'plugin_metadata', 'stream_routes': 'stream_routes',
               'protos': 'proto', 'secrets': 'secrets', 'credentials': 'credentials'}
    for resource, module in modules.items():
        text = (root / f'apisix/admin/{module}.lua').read_text()
        match = re.search(r'unsupported_methods\s*=\s*{([^}]+)}', text)
        unsupported = set(re.findall(r'"([a-z]+)"', match.group(1))) if match else set()
        actual = set()
        for path, item in document['paths'].items():
            if resource == 'credentials':
                relevant = '/consumers/{username}/credentials' in path
            else:
                relevant = path.startswith('/apisix/admin/' + resource) and (
                    path == '/apisix/admin/' + resource or
                    path.startswith('/apisix/admin/' + resource + '/'))
                if resource == 'consumers' and '/credentials' in path:
                    relevant = False
            if relevant:
                actual.update(METHODS & item.keys())
        expected = {'get', 'put', 'post', 'patch', 'delete'} - unsupported
        if actual != expected:
            errors.append(f'{resource}: documented methods {sorted(actual)} != {sorted(expected)}')

    # Resource.put accepts a body ID when the canonical item URL is omitted.
    expected_ops = set()
    for resource, module in modules.items():
        if resource == 'credentials':
            base = '/apisix/admin/consumers/{username}/credentials'
        else:
            base = '/apisix/admin/' + resource
        text = (root / f'apisix/admin/{module}.lua').read_text()
        match = re.search(r'unsupported_methods\s*=\s*{([^}]+)}', text)
        unsupported = set(re.findall(r'"(\w+)"', match.group(1))) if match else set()
        suffix = '/{username}' if resource == 'consumers' else '/{plugin_name}' if resource == 'plugin_metadata' else '/{secret_type}/{id}' if resource == 'secrets' else '/{id}'
        item = base + suffix
        expected_ops.update([(base, 'get'), (item, 'get'), (item, 'put'), (item, 'delete')])
        if resource not in ('secrets', 'plugin_metadata'):
            expected_ops.add((base, 'put'))
        if 'post' not in unsupported:
            expected_ops.add((base, 'post'))
        if 'patch' not in unsupported:
            expected_ops.update([(item, 'patch'), (item + '/{sub_path}', 'patch')])
    expected_ops.add(('/apisix/admin/secrets/{secret_type}', 'get'))
    expected_ops.update({
        ('/apisix/admin/plugins/{plugin_name}', 'get'),
        ('/apisix/admin/schema/plugins/{plugin_name}', 'get'),
        ('/apisix/admin/plugins', 'get'), ('/apisix/admin/plugins/list', 'get'),
        ('/apisix/admin/plugins/reload', 'put'),
        ('/apisix/admin/schema/{resource}', 'get'),
        ('/apisix/admin/schema/validate/{resource}', 'post'),
        ('/apisix/admin', 'head'), ('/apisix/admin/configs', 'get'),
        ('/apisix/admin/configs', 'put'), ('/apisix/admin/configs', 'head'),
        ('/apisix/admin/configs/validate', 'post'),
        ('/apisix/admin/services/{service_id}/graphql_cost_decorations', 'get'),
        ('/apisix/admin/services/{service_id}/graphql_cost_decorations', 'post'),
        ('/apisix/admin/services/{service_id}/graphql_cost_decorations/{decoration_id}', 'get'),
        ('/apisix/admin/services/{service_id}/graphql_cost_decorations/{decoration_id}', 'put'),
        ('/apisix/admin/services/{service_id}/graphql_cost_decorations/{decoration_id}', 'patch'),
        ('/apisix/admin/services/{service_id}/graphql_cost_decorations/{decoration_id}', 'delete'),
    })
    actual_ops = {(path, method) for path, item in document['paths'].items()
                  for method in METHODS & item.keys()}
    if actual_ops != expected_ops:
        errors.append(f'operation surface differs: missing {sorted(expected_ops - actual_ops)}, extra {sorted(actual_ops - expected_ops)}')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('spec', nargs='?', type=Path, default=ROOT / 'docs/en/latest/admin-api.json')
    args = parser.parse_args()
    spec_text = args.spec.read_text()
    if re.search(r'api7|apiseven', spec_text, re.IGNORECASE):
        print('Admin API specification must not contain API7-specific references', file=sys.stderr)
        return 1
    document = json.loads(spec_text)
    errors = validate(document, repository_versions(ROOT))
    if not errors:
        errors.extend(validate_source(document, ROOT))
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print('Admin API OpenAPI 3.1 contract is valid (refs, operations, schemas, examples, defaults, versions, release source constraints and methods).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
