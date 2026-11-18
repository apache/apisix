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

"""Regression checks for the offline Admin API contract validator."""
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
MODULE = importlib.util.spec_from_file_location('admin_contract', ROOT / 'utils/validate-admin-api.py')
validator = importlib.util.module_from_spec(MODULE)
MODULE.loader.exec_module(validator)


class ContractValidationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.document = json.loads((ROOT / 'docs/en/latest/admin-api.json').read_text())
        cls.versions = validator.repository_versions(ROOT)

    def test_release_contract(self):
        self.assertEqual([], validator.validate(self.document, self.versions))
        self.assertEqual([], validator.validate_source(self.document, ROOT))

    def test_unresolved_reference(self):
        document = deepcopy(self.document)
        document['components']['schemas']['Route']['properties']['upstream'] = {
            '$ref': '#/components/schemas/Missing'}
        self.assertTrue(validator.validate(document, self.versions))

    def test_duplicate_operation_and_missing_path_parameter(self):
        document = deepcopy(self.document)
        operations = document['paths']['/apisix/admin/routes/{id}']
        operations['put']['operationId'] = operations['get']['operationId']
        operations['put']['parameters'] = []
        errors = validator.validate(document, self.versions)
        self.assertTrue(errors)
        document = deepcopy(self.document)
        document['paths']['/apisix/admin/routes/{id}']['put']['parameters'] = []
        self.assertTrue(validator.validate(document, self.versions))

    def test_invalid_default_and_response_example(self):
        document = deepcopy(self.document)
        document['components']['schemas']['Route']['properties']['status']['default'] = 9
        media = document['paths']['/apisix/admin/routes']['get']['responses']['200']['content']['application/json']
        media['examples'] = {'invalid': {'value': {'total': 'one', 'list': []}}}
        errors = validator.validate(document, self.versions)
        self.assertTrue(errors)
        document['components']['schemas']['Route']['properties']['status']['default'] = 1
        self.assertTrue(validator.validate(document, self.versions))

    def test_version_and_release_schema_drift(self):
        document = deepcopy(self.document)
        document['info']['version'] = '3.18.0'
        self.assertTrue(validator.validate(document, self.versions))
        del document['components']['schemas']['StreamRoute']['properties']['tls_passthrough']
        self.assertTrue(validator.validate_source(document, ROOT))

    def test_unsupported_method(self):
        document = deepcopy(self.document)
        document['paths']['/apisix/admin/stream_routes/{id}']['patch'] = {}
        self.assertTrue(validator.validate_source(document, ROOT))

    def test_malformed_operation_id(self):
        document = deepcopy(self.document)
        document['paths']['/apisix/admin/stream_routes/{id}']['get']['operationId'] = 'getId]'
        self.assertTrue(validator.validate(document, self.versions))

    def test_missing_collection_put(self):
        document = deepcopy(self.document)
        del document['paths']['/apisix/admin/routes']['put']
        self.assertTrue(validator.validate_source(document, ROOT))

    def test_graphql_cost_decoration_schema_drift(self):
        document = deepcopy(self.document)
        document['components']['schemas']['GraphQLCostDecoration'][
            'properties']['field_path']['pattern'] = '^incorrect$'
        self.assertTrue(validator.validate_source(document, ROOT))

    def test_admin_reference_metadata(self):
        schemas = self.document['components']['schemas']

        upstream_type = schemas['Upstream']['properties']['type']
        self.assertNotIn('enum', upstream_type)
        self.assertIn('user-defined balancers', upstream_type['description'])

        enum_fields = {
            'Upstream': ('hash_on', 'scheme', 'pass_host'),
            'Route': ('status',),
            'SSL': ('type', 'status'),
            'SSLRead': ('type', 'status'),
        }
        for schema_name, property_names in enum_fields.items():
            for property_name in property_names:
                prop = schemas[schema_name]['properties'][property_name]
                self.assertEqual(
                    {str(value) for value in prop['enum']},
                    set(prop['x-enumDescriptions']),
                )

        secret_patch = schemas['SecretPatch']
        self.assertEqual(3, len(secret_patch['anyOf']))
        self.assertEqual(
            {'HashiCorp Vault', 'AWS Secrets Manager',
             'Google Cloud Secret Manager'},
            {branch['title'] for branch in secret_patch['anyOf']},
        )
        for value in (
                {'token': None},
                {'session_token': None},
                {'auth_config': {'client_email': None}}):
            errors = validator.Draft202012Validator(secret_patch).iter_errors(value)
            self.assertFalse(list(errors))

    def test_unconstrained_array_items_are_explicit(self):
        document = deepcopy(self.document)
        del document['components']['schemas']['Route'][
            'properties']['vars']['items']
        errors = validator.validate(document, self.versions)
        self.assertTrue(any(
            'array schema must declare items' in error for error in errors))


if __name__ == '__main__':
    unittest.main()
