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

"""Validate the checked-in Control API contract against this checkout."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
ADMIN_VALIDATOR_PATH = ROOT / 'utils/validate-admin-api.py'
MODULE = importlib.util.spec_from_file_location('admin_contract', ADMIN_VALIDATOR_PATH)
common = importlib.util.module_from_spec(MODULE)
MODULE.loader.exec_module(common)

METHODS = common.METHODS


def operations(document):
    return {(path, method) for path, item in document.get('paths', {}).items()
            for method in METHODS & item.keys()}


def core_operations(root):
    """Extract the built-in v1 route table and expand its wildcard contracts."""
    text = (root / 'apisix/control/v1.lua').read_text()
    route_table = text.rsplit('return {', 1)[1]
    routes = re.findall(
        r'\{\s*methods\s*=\s*\{([^}]*)\}\s*,?\s*'
        r'uris\s*=\s*\{([^}]*)\}',
        route_table,
        re.DOTALL,
    )
    method_entries = len(re.findall(r'\bmethods\s*=', route_table))
    if len(routes) != method_entries:
        raise ValueError(
            f'could not parse {method_entries - len(routes)} Control API route entries'
        )
    expanded = set()
    wildcard_paths = {
        '/healthcheck/*': (
            '/v1/healthcheck/{src_type}/{src_id}',
            '/v1/healthcheck/{src_type}/{src_id}/checkers',
        ),
        '/route/*': ('/v1/route/{route_id}',),
        '/service/*': ('/v1/service/{service_id}',),
        '/upstream/*': ('/v1/upstream/{upstream_id}',),
        '/plugin_metadata/*': ('/v1/plugin_metadata/{plugin_name}',),
    }
    for methods_source, paths_source in routes:
        methods = re.findall(r'"([A-Z]+)"', methods_source)
        paths = re.findall(r'"(/[^"]+)"', paths_source)
        if not methods or not paths:
            raise ValueError('Control API route entry has no parseable method or URI')
        for method in methods:
            for path in paths:
                for contract_path in wildcard_paths.get(path, ('/v1' + path,)):
                    expanded.add((contract_path, method.lower()))
    return expanded


def optional_operations(root):
    """Return stable patterns registered by shipped optional components."""
    result = set()
    server_info = (root / 'apisix/plugins/server-info.lua').read_text()
    if 'function _M.control_api()' in server_info and '"/v1/server_info"' in server_info:
        result.add(('/v1/server_info', 'get'))

    discovery_sources = list((root / 'apisix/discovery').glob('*/init.lua'))
    if any('function _M.dump_data()' in source.read_text() for source in discovery_sources):
        result.add(('/v1/discovery/{service}/dump', 'get'))
    if any('function _M.control_api()' in source.read_text() and
           '"/show_dump_file"' in source.read_text() for source in discovery_sources):
        result.add(('/v1/discovery/{service}/show_dump_file', 'get'))
    return result


def validate_response_contract(document):
    """Protect source-verified response details that generic OAS lint cannot infer."""
    errors = []

    def get(*parts):
        value = document
        for part in parts:
            if not isinstance(value, dict) or part not in value:
                return None
            value = value[part]
        return value

    for path in ('/v1/route/{route_id}', '/v1/upstream/{upstream_id}'):
        example = get('paths', path, 'get', 'responses', '200', 'content',
                      'application/json', 'examples', '1', 'value')
        if not isinstance(example, dict) or not isinstance(example.get('value'), dict):
            errors.append(f'GET {path}: example must preserve the config-entry value envelope')

    for path in ('/v1/routes', '/v1/services', '/v1/upstreams',
                 '/v1/plugin_metadatas'):
        schema = get('paths', path, 'get', 'responses', '200', 'content',
                     'application/json', 'schema') or {}
        choices = schema.get('oneOf', []) if isinstance(schema, dict) else []
        types = {choice.get('type') for choice in choices if isinstance(choice, dict)}
        empty_object = any(choice.get('type') == 'object' and
                           choice.get('maxProperties') == 0 for choice in choices
                           if isinstance(choice, dict))
        if types != {'array', 'object'} or not empty_object:
            errors.append(f'GET {path}: schema must include the runtime empty-object response')

    dump_content = get('paths', '/v1/discovery/{service}/show_dump_file',
                       'get', 'responses', '200', 'content')
    if not isinstance(dump_content, dict) or set(dump_content) != {'text/plain'}:
        errors.append('discovery dump-file response must be JSON text with text/plain media type')

    server_text = ' '.join([
        str(get('paths', '/v1/server_info', 'get', 'description') or ''),
        *(str(tag.get('description', '')) for tag in document.get('tags', [])
          if tag.get('name') == 'Server Information'),
    ])
    if 'deprecated in APISIX 3.13.0' not in server_text or '3.17.0' in server_text:
        errors.append('server-info deprecation must identify APISIX 3.13.0')

    plugin_parameters = get('paths', '/v1/plugin_metadata/{plugin_name}',
                            'get', 'parameters') or []
    plugin_example = next((parameter.get('example') for parameter in plugin_parameters
                           if parameter.get('name') == 'plugin_name'), None)
    if plugin_example != 'file-logger':
        errors.append('plugin_name must use a non-empty source-backed example')

    server_id = get('paths', '/v1/server_info', 'get', 'responses', '200',
                    'content', 'application/json', 'schema', 'properties', 'id') or {}
    id_choices = server_id.get('oneOf', []) if isinstance(server_id, dict) else []
    if {choice.get('type') for choice in id_choices if isinstance(choice, dict)} != {
            'string', 'integer'}:
        errors.append('server_info.id must allow generated strings and configured integers')

    reload_response = get('paths', '/v1/plugins/reload', 'put', 'responses', '503') or {}
    reload_content = reload_response.get('content', {})
    reload_description = reload_response.get('description', '').lower()
    if (set(reload_content) != {'text/plain'} or
            'recorded' not in reload_description or 'published' not in reload_description):
        errors.append('plugin reload 503 must cover both failure paths as text/plain')

    expected_errors = {
        ('/v1/healthcheck/{src_type}/{src_id}', '400'): 'invalid src type route',
        ('/v1/healthcheck/{src_type}/{src_id}', '404'): 'routes[1] not found',
        ('/v1/healthcheck/{src_type}/{src_id}/checkers', '400'): 'invalid src type route',
        ('/v1/healthcheck/{src_type}/{src_id}/checkers', '404'): 'routes[1] not found',
        ('/v1/route/{route_id}', '404'): 'route[2] not found',
        ('/v1/service/{service_id}', '404'): 'service[2] not found',
        ('/v1/upstream/{upstream_id}', '404'): 'upstream[3] not found',
        ('/v1/plugin_metadata/{plugin_name}', '404'):
            'plugin metadata[missing-plugin] not found',
    }
    for (path, status), expected in expected_errors.items():
        actual = get('paths', path, 'get', 'responses', status, 'content',
                     'application/json', 'schema', 'properties', 'error_msg', 'example')
        if actual != expected:
            errors.append(f'GET {path} {status}: error_msg example must be {expected!r}')
    return errors


def validate_source(document, root):
    errors = []
    expected = core_operations(root) | optional_operations(root)
    actual = operations(document)
    if actual != expected:
        errors.append(
            f'operation surface differs: missing {sorted(expected - actual)}, '
            f'extra {sorted(actual - expected)}'
        )

    description = document.get('info', {}).get('description', '')
    if 'Enabled plugins and service discovery modules can register additional endpoints' not in description:
        errors.append('info.description must distinguish configuration-dependent endpoints')
    if re.search(r'api7|apiseven', json.dumps(document), re.IGNORECASE):
        errors.append('Control API specification must not contain API7-specific references')
    if document.get('security') != []:
        errors.append('Control API must explicitly declare that it has no authentication')
    servers = document.get('servers', [])
    if len(servers) != 1 or servers[0].get('url') != 'http://127.0.0.1:9090':
        errors.append('Control API must document only the default loopback server')

    conditional = {
        '/v1/server_info': ('only when', '`server-info` plugin'),
        '/v1/discovery/{service}/dump': ('only when', 'service discovery module'),
        '/v1/discovery/{service}/show_dump_file': ('only when', 'service discovery module'),
    }
    for path, phrases in conditional.items():
        operation = document.get('paths', {}).get(path, {}).get('get', {})
        text = operation.get('description', '')
        for phrase in phrases:
            if phrase not in text:
                errors.append(f'GET {path}: description must include {phrase!r}')
    errors.extend(validate_response_contract(document))
    return errors


def validate(document, root=ROOT):
    errors = common.validate(document, common.repository_versions(root))
    errors.extend(validate_source(document, root))
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        'spec',
        nargs='?',
        type=Path,
        default=ROOT / 'docs/en/latest/control-api.json',
    )
    args = parser.parse_args()
    document = json.loads(args.spec.read_text())
    errors = validate(document)
    if errors:
        print('\n'.join(f'- {error}' for error in errors), file=sys.stderr)
        return 1
    operation_count = len(operations(document))
    schema_count = len(document.get('components', {}).get('schemas', {}))
    print(f'Control API contract is valid: {operation_count} operations, {schema_count} schemas')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
