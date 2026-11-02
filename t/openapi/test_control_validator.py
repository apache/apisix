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

"""Regression checks for the offline Control API contract validator."""
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MODULE = importlib.util.spec_from_file_location(
    'control_contract', ROOT / 'utils/validate-control-api.py')
validator = importlib.util.module_from_spec(MODULE)
MODULE.loader.exec_module(validator)


class ControlContractValidationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.document = json.loads(
            (ROOT / 'docs/en/latest/control-api.json').read_text())

    def test_contract(self):
        self.assertEqual([], validator.validate(self.document, ROOT))

    def test_missing_core_operation(self):
        document = deepcopy(self.document)
        del document['paths']['/v1/schema']
        self.assertTrue(validator.validate_source(document, ROOT))

    def test_unregistered_operation(self):
        document = deepcopy(self.document)
        document['paths']['/v1/not_registered'] = {
            'get': {
                'operationId': 'getUnregistered',
                'responses': {'200': {'description': 'OK'}},
            }
        }
        self.assertTrue(validator.validate_source(document, ROOT))

    def test_downstream_reference(self):
        document = deepcopy(self.document)
        document['info']['description'] += ' https://docs.api7.ai/apisix'
        self.assertTrue(validator.validate_source(document, ROOT))

    def test_conditional_endpoint_must_be_qualified(self):
        document = deepcopy(self.document)
        document['paths']['/v1/server_info']['get']['description'] = (
            'Get information about the local APISIX instance.')
        self.assertTrue(validator.validate_source(document, ROOT))

    def test_control_api_security_boundary(self):
        document = deepcopy(self.document)
        document['security'] = [{'ApiKey': []}]
        document['servers'][0]['url'] = 'http://0.0.0.0:9090'
        errors = validator.validate_source(document, ROOT)
        self.assertGreaterEqual(len(errors), 2)

    def test_version_and_openapi_validation(self):
        document = deepcopy(self.document)
        document['info']['version'] = '3.18.0'
        self.assertTrue(validator.validate(document, ROOT))

    def test_core_parser_accepts_multiple_methods_and_rejects_unknown_shape(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'apisix/control/v1.lua'
            source.parent.mkdir(parents=True)
            source.write_text(
                'return { { methods = {"GET", "HEAD"}, '
                'uris = {"/new_multi"}, handler = handler } }')
            self.assertEqual(
                {('/v1/new_multi', 'get'), ('/v1/new_multi', 'head')},
                validator.core_operations(root),
            )
            source.write_text(
                'return { { methods = allowed_methods, '
                'uris = {"/unknown"}, handler = handler } }')
            with self.assertRaises(ValueError):
                validator.core_operations(root)

    def test_source_backed_response_invariants(self):
        mutations = []

        document = deepcopy(self.document)
        document['paths']['/v1/route/{route_id}']['get']['responses']['200'][
            'content']['application/json']['examples']['1']['value'] = {'id': '1'}
        mutations.append(document)

        document = deepcopy(self.document)
        response = document['paths'][
            '/v1/discovery/{service}/show_dump_file']['get']['responses']['200']
        response['content'] = {'application/json': {'schema': {'type': 'object'}}}
        mutations.append(document)

        document = deepcopy(self.document)
        document['paths']['/v1/server_info']['get']['description'] = (
            document['paths']['/v1/server_info']['get']['description']
            .replace('3.13.0', '3.17.0'))
        mutations.append(document)

        document = deepcopy(self.document)
        document['paths']['/v1/plugins/reload']['put']['responses']['503'][
            'content'] = {'application/json': {'schema': {'type': 'object'}}}
        mutations.append(document)

        document = deepcopy(self.document)
        document['paths']['/v1/route/{route_id}']['get']['responses']['404'][
            'content']['application/json']['schema']['properties']['error_msg'][
                'example'] = 'Resource not found.'
        mutations.append(document)

        document = deepcopy(self.document)
        document['paths']['/v1/routes']['get']['responses']['200'][
            'content']['application/json']['schema'] = {'type': 'array'}
        mutations.append(document)

        document = deepcopy(self.document)
        document['paths']['/v1/server_info']['get']['responses']['200'][
            'content']['application/json']['schema']['properties']['id'] = {
                'type': 'string'}
        mutations.append(document)

        for document in mutations:
            self.assertTrue(validator.validate_response_contract(document))


if __name__ == '__main__':
    unittest.main()
