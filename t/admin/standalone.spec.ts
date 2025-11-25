/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import axios from 'axios';
import YAML from 'yaml';

const ENDPOINT = '/apisix/admin/configs';
const VALIDATE_ENDPOINT = '/apisix/admin/configs/validate';
const HEADER_LAST_MODIFIED = 'x-last-modified';
const HEADER_DIGEST = 'x-digest';
const clientConfig = {
  baseURL: 'http://localhost:1984',
  headers: {
    'X-API-KEY': 'edd1c9f034335f136f87ad84b625c8f1',
  },
};
const config1 = {
  routes: [
    {
      id: 'r1',
      uri: '/r1',
      upstream: {
        nodes: { '127.0.0.1:1980': 1 },
        type: 'roundrobin',
      },
      plugins: { 'proxy-rewrite': { uri: '/hello' } },
    },
  ],
};
const config2 = {
  routes: [
    {
      id: 'r2',
      uri: '/r2',
      upstream: {
        nodes: { '127.0.0.1:1980': 1 },
        type: 'roundrobin',
      },
      plugins: { 'proxy-rewrite': { uri: '/hello' } },
    },
  ],
};
const invalidConfVersionConfig1 = {
  routes_conf_version: -1,
};
const invalidConfVersionConfig2 = {
  routes_conf_version: 'adc',
};
const routeWithModifiedIndex = {
  routes: [
    {
      id: 'r1',
      uri: '/r1',
      modifiedIndex: 1,
      upstream: {
        nodes: { '127.0.0.1:1980': 1 },
        type: 'roundrobin',
      },
      plugins: { 'proxy-rewrite': { uri: '/hello' } },
    },
  ],
};
const routeWithKeyAuth = {
  routes: [
    {
      id: 'r1',
      uri: '/r1',
      upstream: {
        nodes: { '127.0.0.1:1980': 1 },
        type: 'roundrobin',
      },
      plugins: {
        'proxy-rewrite': { uri: '/hello' },
        'key-auth': {},
      },
    },
  ],
};
const consumerWithModifiedIndex = {
  routes: routeWithKeyAuth.routes,
  consumers: [
    {
      modifiedIndex: 10,
      username: 'jack',
      plugins: {
        'key-auth': {
          key: 'jack-key',
        },
      },
    },
  ],
};
const credential1 = {
  routes: routeWithKeyAuth.routes,
  consumers: [
    {
      username: 'john_1',
    },
    {
      id: 'john_1/credentials/john-a',
      plugins: {
        'key-auth': {
          key: 'auth-a',
        },
      },
    },
    {
      id: 'john_1/credentials/john-b',
      plugins: {
        'key-auth': {
          key: 'auth-b',
        },
      },
    },
  ],
};

const unknownPlugins = {
  'invalid-plugin': {},
};

const routeWithUnknownPlugins = {
  routes: [
    {
      id: 'r1',
      uri: '/r1',
      plugins: unknownPlugins,
    },
  ],
};

const servicesWithUnknownPlugins = {
  services: [
    {
      id: 's1',
      name: 's1',
      plugins: unknownPlugins,
    },
  ],
};

const invalidUpstream = {
  nodes: { '127.0.0.1:1980': 1 },
  type: 'chash',
  hash_on: 'vars',
  key: 'args_invalid',
};

const routeWithInvalidUpstream = {
  routes: [
    {
      id: 'r1',
      uri: '/r1',
      upstream: invalidUpstream,
    },
  ],
};

const serviceWithInvalidUpstream = {
  services: [
    {
      id: 's1',
      name: 's1',
      upstream: invalidUpstream,
    },
  ],
};

let mockDigest = 1;

describe('Admin - Standalone', () => {
  const client = axios.create(clientConfig);
  client.interceptors.response.use((response) => {
    const contentType = response.headers['content-type'] || '';
    if (
      contentType.includes('application/yaml') &&
      typeof response.data === 'string' &&
      response.config.responseType !== 'text'
    )
      response.data = YAML.parse(response.data);
    return response;
  });

  describe('Normal', () => {
    it('dump empty config (default json format)', async () => {
      const resp = await client.get(ENDPOINT);
      expect(resp.status).toEqual(200);
      expect(resp.data.routes_conf_version).toEqual(0);
      expect(resp.data.ssls_conf_version).toEqual(0);
      expect(resp.data.services_conf_version).toEqual(0);
      expect(resp.data.upstreams_conf_version).toEqual(0);
      expect(resp.data.consumers_conf_version).toEqual(0);
      expect(resp.headers[HEADER_LAST_MODIFIED]).toBe(undefined);
      expect(resp.headers[HEADER_DIGEST]).toBe(undefined);
    });

    it('dump empty config (yaml format)', async () => {
      const resp = await client.get(ENDPOINT, {
        headers: { Accept: 'application/yaml' },
      });
      expect(resp.status).toEqual(200);
      expect(resp.headers['content-type']).toEqual('application/yaml');
      expect(resp.data.routes_conf_version).toEqual(0);
      expect(resp.data.ssls_conf_version).toEqual(0);
      expect(resp.data.services_conf_version).toEqual(0);
      expect(resp.data.upstreams_conf_version).toEqual(0);
      expect(resp.data.consumers_conf_version).toEqual(0);
      expect(resp.headers[HEADER_LAST_MODIFIED]).toBe(undefined);
      expect(resp.headers[HEADER_DIGEST]).toBe(undefined);
    });

    it('update config (add routes, by json)', async () => {
      const resp = await client.put(ENDPOINT, config1, {
        headers: { [HEADER_DIGEST]: mockDigest },
      });
      expect(resp.status).toEqual(202);
      expect(parseInt(resp.headers[HEADER_LAST_MODIFIED])).toBeGreaterThan(0);
      expect(resp.headers[HEADER_DIGEST]).toEqual(`${mockDigest}`);
    });

    it('update config (same digest, no update)', async () => {
      const resp = await client.put(ENDPOINT, config1, {
        headers: { [HEADER_DIGEST]: mockDigest },
      });
      expect(resp.status).toEqual(204);
    });

    it('get metadata (by HTTP HEAD method)', async () => {
      const resp = await client.head(ENDPOINT);
      expect(resp.status).toEqual(200);
      expect(parseInt(resp.headers[HEADER_LAST_MODIFIED])).toBeGreaterThan(0);
      expect(resp.headers[HEADER_DIGEST]).toEqual(`${mockDigest}`);
    });

    it('dump config (json format)', async () => {
      const resp = await client.get(ENDPOINT);
      expect(resp.status).toEqual(200);
      expect(resp.data.routes_conf_version).toEqual(1);
      expect(resp.data.ssls_conf_version).toEqual(1);
      expect(resp.data.services_conf_version).toEqual(1);
      expect(resp.data.upstreams_conf_version).toEqual(1);
      expect(resp.data.consumers_conf_version).toEqual(1);
      expect(resp.data.routes).toEqual(config1.routes);
      expect(parseInt(resp.headers[HEADER_LAST_MODIFIED])).toBeGreaterThan(0);
      expect(resp.headers[HEADER_DIGEST]).toEqual(`${mockDigest}`);
    });

    it('dump config (yaml format)', async () => {
      const resp = await client.get(ENDPOINT, {
        headers: { Accept: 'application/yaml' },
        responseType: 'text',
      });
      expect(resp.status).toEqual(200);
      expect(resp.data).toContain('routes:');
      expect(resp.data).toContain('id: r1');
      expect(resp.data.startsWith('---')).toBe(false);
      expect(resp.data.endsWith('...')).toBe(false);
      expect(parseInt(resp.headers[HEADER_LAST_MODIFIED])).toBeGreaterThan(0);
      expect(resp.headers[HEADER_DIGEST]).toEqual(`${mockDigest}`);
    });

    it('check route "r1"', async () => {
      const resp = await client.get('/r1');
      expect(resp.status).toEqual(200);
      expect(resp.data).toEqual('hello world\n');
    });

    it('update config (add routes, by yaml)', async () => {
      mockDigest += 1;
      const resp = await client.put(ENDPOINT, YAML.stringify(config2), {
        headers: {
          'Content-Type': 'application/yaml',
          [HEADER_DIGEST]: mockDigest,
        },
      });
      expect(resp.status).toEqual(202);
    });

    it('dump config (json format)', async () => {
      const resp = await client.get(ENDPOINT);
      expect(resp.status).toEqual(200);
      expect(resp.data.routes_conf_version).toEqual(2);
      expect(resp.data.ssls_conf_version).toEqual(2);
      expect(resp.data.services_conf_version).toEqual(2);
      expect(resp.data.upstreams_conf_version).toEqual(2);
      expect(resp.data.consumers_conf_version).toEqual(2);
      expect(parseInt(resp.headers[HEADER_LAST_MODIFIED])).toBeGreaterThan(0);
      expect(resp.headers[HEADER_DIGEST]).toEqual(`${mockDigest}`);
    });

    it('check route "r1"', () =>
      expect(client.get('/r1')).rejects.toThrow(
        'Request failed with status code 404',
      ));

    it('check route "r2"', async () => {
      const resp = await client.get('/r2');
      expect(resp.status).toEqual(200);
      expect(resp.data).toEqual('hello world\n');
    });

    it('update config (delete routes)', async () => {
      mockDigest += 1;
      const resp = await client.put(
        ENDPOINT,
        {},
        { headers: { [HEADER_DIGEST]: mockDigest } },
      );
      expect(resp.status).toEqual(202);
    });

    it('check route "r2"', () =>
      expect(client.get('/r2')).rejects.toThrow(
        'Request failed with status code 404',
      ));

    it('only set routes_conf_version', async () => {
      mockDigest += 1;
      const resp = await client.put(
        ENDPOINT,
        YAML.stringify({ routes_conf_version: 15 }),
        {
          headers: {
            'Content-Type': 'application/yaml',
            [HEADER_DIGEST]: mockDigest,
          },
        },
      );
      expect(resp.status).toEqual(202);

      const resp_1 = await client.get(ENDPOINT);
      expect(resp_1.status).toEqual(200);
      expect(resp_1.data.routes_conf_version).toEqual(15);
      expect(resp_1.data.ssls_conf_version).toEqual(4);
      expect(resp_1.data.services_conf_version).toEqual(4);
      expect(resp_1.data.upstreams_conf_version).toEqual(4);
      expect(resp_1.data.consumers_conf_version).toEqual(4);
      expect(resp_1.headers[HEADER_DIGEST]).toEqual(`${mockDigest}`);

      mockDigest += 1;
      const resp2 = await client.put(
        ENDPOINT,
        YAML.stringify({ routes_conf_version: 17 }),
        {
          headers: {
            'Content-Type': 'application/yaml',
            [HEADER_DIGEST]: mockDigest,
          },
        },
      );
      expect(resp2.status).toEqual(202);

      const resp2_1 = await client.get(ENDPOINT);
      expect(resp2_1.status).toEqual(200);
      expect(resp2_1.data.routes_conf_version).toEqual(17);
      expect(resp2_1.data.ssls_conf_version).toEqual(5);
      expect(resp2_1.data.services_conf_version).toEqual(5);
      expect(resp2_1.data.upstreams_conf_version).toEqual(5);
      expect(resp2_1.data.consumers_conf_version).toEqual(5);
      expect(resp2_1.headers[HEADER_DIGEST]).toEqual(`${mockDigest}`);
    });

    it('control resource changes using modifiedIndex', async () => {
      const c1 = structuredClone(routeWithModifiedIndex);
      c1.routes[0].modifiedIndex = 1;

      const c2 = structuredClone(c1);
      c2.routes[0].uri = '/r2';

      const c3 = structuredClone(c2);
      c3.routes[0].modifiedIndex = 2;

      // Update with c1
      mockDigest += 1;
      const resp = await client.put(ENDPOINT, c1, {
        headers: { [HEADER_DIGEST]: mockDigest },
      });
      expect(resp.status).toEqual(202);

      // Check route /r1 exists
      const resp_1 = await client.get('/r1');
      expect(resp_1.status).toEqual(200);

      // Update with c2
      mockDigest += 1;
      const resp2 = await client.put(ENDPOINT, c2, {
        headers: { [HEADER_DIGEST]: mockDigest },
      });
      expect(resp2.status).toEqual(202);

      // Check route /r1 exists
      // But it is not applied because the modifiedIndex is the same as the old value
      const resp2_2 = await client.get('/r1');
      expect(resp2_2.status).toEqual(200);

      // Check route /r2 not exists
      const resp2_1 = await client.get('/r2').catch((err) => err.response);
      expect(resp2_1.status).toEqual(404);

      // Update with c3
      mockDigest += 1;
      const resp3 = await client.put(ENDPOINT, c3, {
        headers: { [HEADER_DIGEST]: mockDigest },
      });
      expect(resp3.status).toEqual(202);

      // Check route /r1 not exists
      const resp3_1 = await client.get('/r1').catch((err) => err.response);
      expect(resp3_1.status).toEqual(404);

      // Check route /r2 exists
      const resp3_2 = await client.get('/r2');
      expect(resp3_2.status).toEqual(200);
    });

    it('apply consumer with modifiedIndex', async () => {
      mockDigest += 1;
      const resp = await client.put(ENDPOINT, consumerWithModifiedIndex, {
        headers: { [HEADER_DIGEST]: mockDigest },
      });
      expect(resp.status).toEqual(202);

      const resp_1 = await client
        .get('/r1', { headers: { apikey: 'invalid-key' } })
        .catch((err) => err.response);
      expect(resp_1.status).toEqual(401);
      const resp_2 = await client.get('/r1', {
        headers: { apikey: 'jack-key' },
      });
      expect(resp_2.status).toEqual(200);

      const updatedConsumer = structuredClone(consumerWithModifiedIndex);

      // update key of key-auth plugin, but modifiedIndex is not changed
      updatedConsumer.consumers[0].plugins['key-auth'] = {
        key: 'jack-key-updated',
      };
      mockDigest += 1;
      const resp2 = await client.put(ENDPOINT, updatedConsumer, {
        headers: { [HEADER_DIGEST]: mockDigest },
      });
      expect(resp2.status).toEqual(202);

      const resp2_1 = await client
        .get('/r1', { headers: { apikey: 'jack-key-updated' } })
        .catch((err) => err.response);
      expect(resp2_1.status).toEqual(401);
      const resp2_2 = await client.get('/r1', {
        headers: { apikey: 'jack-key' },
      });
      expect(resp2_2.status).toEqual(200);

      // update key of key-auth plugin, and modifiedIndex is changed
      updatedConsumer.consumers[0].modifiedIndex++;
      mockDigest += 1;
      const resp3 = await client.put(ENDPOINT, updatedConsumer, {
        headers: { [HEADER_DIGEST]: mockDigest },
      });
      const resp3_1 = await client.get('/r1', {
        headers: { apikey: 'jack-key-updated' },
      });
      expect(resp3_1.status).toEqual(200);
      const resp3_2 = await client
        .get('/r1', { headers: { apikey: 'jack-key' } })
        .catch((err) => err.response);
      expect(resp3_2.status).toEqual(401);
    });

    it('apply consumer with credentials', async () => {
      mockDigest += 1;
      const resp = await client.put(ENDPOINT, credential1, {
        headers: { [HEADER_DIGEST]: mockDigest },
      });
      expect(resp.status).toEqual(202);

      const resp_1 = await client.get('/r1', { headers: { apikey: 'auth-a' } });
      expect(resp_1.status).toEqual(200);
      const resp_2 = await client.get('/r1', { headers: { apikey: 'auth-b' } });
      expect(resp_2.status).toEqual(200);
      const resp_3 = await client
        .get('/r1', { headers: { apikey: 'invalid-key' } })
        .catch((err) => err.response);
      expect(resp_3.status).toEqual(401);
    });
  });

  describe('Exceptions', () => {
    const clientException = axios.create({
      ...clientConfig,
      validateStatus: () => true,
    });

    it('update config (without digest)', async () => {
      const resp = await clientException.put(ENDPOINT, {
        routes_conf_version: 100,
      });
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({ error_msg: 'missing digest header' });
    });

    it('update config (lower conf_version)', async () => {
      mockDigest += 1;
      const resp = await clientException.put(
        ENDPOINT,
        { routes_conf_version: 100 },
        { headers: { [HEADER_DIGEST]: mockDigest } },
      );
      expect(resp.status).toEqual(202);

      mockDigest += 1;
      const resp2 = await clientException.put(
        ENDPOINT,
        YAML.stringify(invalidConfVersionConfig1),
        {
          headers: {
            'Content-Type': 'application/yaml',
            [HEADER_DIGEST]: mockDigest,
          },
        },
      );
      expect(resp2.status).toEqual(400);
      expect(resp2.data).toEqual({
        error_msg: 'routes_conf_version must be greater than or equal to (100)',
      });
    });

    it('update config (invalid conf_version)', async () => {
      const resp = await clientException.put(
        ENDPOINT,
        YAML.stringify(invalidConfVersionConfig2),
        {
          headers: {
            'Content-Type': 'application/yaml',
            [HEADER_DIGEST]: mockDigest,
          },
        },
      );
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({
        error_msg: 'routes_conf_version must be a number',
      });
    });

    it('update config (invalid json format)', async () => {
      const resp = await clientException.put(ENDPOINT, '{abcd', {
        headers: { [HEADER_DIGEST]: mockDigest },
      });
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({
        error_msg:
          'invalid request body: Expected object key string but found invalid token at character 2',
      });
    });

    it('update config (not compliant with jsonschema)', async () => {
      const data = structuredClone(config1);
      (data.routes[0].uri as unknown) = 123;
      const resp = await clientException.put(ENDPOINT, data, {
        headers: { [HEADER_DIGEST]: mockDigest },
      });
      expect(resp.status).toEqual(400);
      expect(resp.data).toMatchObject({
        error_msg:
          'invalid routes at index 0, err: invalid configuration: property "uri" validation failed: wrong type: expected string, got number',
      });
    });

    it('update config (empty request body)', async () => {
      const resp = await clientException.put(ENDPOINT, '', {
        headers: { [HEADER_DIGEST]: mockDigest },
      });
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({
        error_msg: 'invalid request body: empty request body',
      });
    });

    it('update config (invalid plugin)', async () => {
      const resp = await clientException.put(
        ENDPOINT,
        servicesWithUnknownPlugins,
        {
          headers: { [HEADER_DIGEST]: mockDigest },
        },
      );
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({
        error_msg:
          'invalid services at index 0, err: unknown plugin [invalid-plugin]',
      });
      const resp2 = await clientException.put(
        ENDPOINT,
        routeWithUnknownPlugins,
        {
          headers: { [HEADER_DIGEST]: mockDigest },
        },
      );
      expect(resp2.status).toEqual(400);
      expect(resp2.data).toEqual({
        error_msg:
          'invalid routes at index 0, err: unknown plugin [invalid-plugin]',
      });
    });

    it('update config (invalid upstream)', async () => {
      const resp = await clientException.put(
        ENDPOINT,
        serviceWithInvalidUpstream,
        {
          headers: { [HEADER_DIGEST]: mockDigest },
        },
      );
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({
        error_msg:
          'invalid services at index 0, err: invalid configuration: failed to match pattern "^((uri|server_name|server_addr|request_uri|remote_port|remote_addr|query_string|host|hostname|mqtt_client_id)|arg_[0-9a-zA-z_-]+)$" with "args_invalid"',
      });

      const resp2 = await clientException.put(
        ENDPOINT,
        routeWithInvalidUpstream,
        {
          headers: { [HEADER_DIGEST]: mockDigest },
        },
      );
      expect(resp2.status).toEqual(400);
      expect(resp2.data).toEqual({
        error_msg:
          'invalid routes at index 0, err: invalid configuration: failed to match pattern "^((uri|server_name|server_addr|request_uri|remote_port|remote_addr|query_string|host|hostname|mqtt_client_id)|arg_[0-9a-zA-z_-]+)$" with "args_invalid"',
      });
    });
  });
});

describe('Validate API - Standalone', () => {
  const client = axios.create(clientConfig);
  client.interceptors.response.use((response) => {
    const contentType = response.headers['content-type'] || '';
    if (
      contentType.includes('application/yaml') &&
      typeof response.data === 'string' &&
      response.config.responseType !== 'text'
    )
      response.data = YAML.parse(response.data);
    return response;
  });
  describe('Normal', () => {
    it('validate config (success case with json)', async () => {
      const resp = await client.post(VALIDATE_ENDPOINT, config1);
      expect(resp.status).toEqual(200);
    });

    it('validate config (success case with yaml)', async () => {
      const resp = await client.post(VALIDATE_ENDPOINT, YAML.stringify(config1), {
        headers: { 'Content-Type': 'application/yaml' },
      });
      expect(resp.status).toEqual(200);
    });

    it('validate config (success case with multiple resources)', async () => {
      const multiResourceConfig = {
        routes: [
          {
            id: 'r1',
            uri: '/r1',
            upstream: {
              nodes: { '127.0.0.1:1980': 1 },
              type: 'roundrobin',
            },
          },
          {
            id: 'r2',
            uri: '/r2',
            upstream: {
              nodes: { '127.0.0.1:1980': 1 },
              type: 'roundrobin',
            },
          },
        ],
        services: [
          {
            id: 's1',
            upstream: {
              nodes: { '127.0.0.1:1980': 1 },
              type: 'roundrobin',
            },
          },
        ],
        routes_conf_version: 1,
        services_conf_version: 1,
      };

      const resp = await client.post(VALIDATE_ENDPOINT, multiResourceConfig);
      expect(resp.status).toEqual(200);
    });

    it('validate config with consumer credentials', async () => {
      const resp = await client.post(VALIDATE_ENDPOINT, credential1);
      expect(resp.status).toEqual(200);
    });

    it('validate config does not persist changes', async () => {
      // First validate a configuration
      const validateResp = await client.post(VALIDATE_ENDPOINT, config1);
      expect(validateResp.status).toEqual(200);

      // Then check that the configuration was not persisted
      const getResp = await client.get(ENDPOINT);
      expect(getResp.data.routes).toBeUndefined();
    });
  });
  describe('Exceptions', () => {
    const clientException = axios.create({
      ...clientConfig,
      validateStatus: () => true,
    });
    it('validate config (duplicate route id)', async () => {
      const duplicateConfig = {
        routes: [
          {
            id: 'r1',
            uri: '/r1',
            upstream: {
              nodes: { '127.0.0.1:1980': 1 },
              type: 'roundrobin',
            },
          },
          {
            id: 'r1', // Duplicate ID
            uri: '/r2',
            upstream: {
              nodes: { '127.0.0.1:1980': 1 },
              type: 'roundrobin',
            },
          },],
      };

      const resp = await clientException.post(VALIDATE_ENDPOINT, duplicateConfig);
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({
        error_msg: 'Configuration validation failed',
        errors: expect.arrayContaining([
          expect.objectContaining({
            resource_type: 'routes',
            error: expect.stringContaining('found duplicate id r1 in routes'),
          }),
        ]),
      });
    });

    it('validate config (invalid route configuration)', async () => {
      const invalidConfig = {
        routes: [
          {
            id: 'r1',
            uri: '/r1',
            upstream: {
              nodes: { '127.0.0.1:1980': 1 },
              type: 'roundrobin',
              // Add an invalid field that should definitely fail validation
              invalid_field: 'this_should_fail'
            },
          },
        ],
      };

      const resp = await clientException.post(VALIDATE_ENDPOINT, invalidConfig);
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({
        error_msg: 'Configuration validation failed',
        errors: expect.arrayContaining([
          expect.objectContaining({
            resource_type: 'routes',
            error: expect.stringContaining('invalid routes at index 0'),
          }),
        ]),
      });
    });

    it('validate config (invalid version number)', async () => {
      const invalidVersionConfig = {
        routes: [
          {
            id: 'r1',
            uri: '/r1',
            upstream: {
              nodes: { '127.0.0.1:1980': 1 },
              type: 'roundrobin',
            },
          },
        ],
        routes_conf_version: 'not_a_number', // Invalid version type
      };

      const resp = await clientException.post(VALIDATE_ENDPOINT, invalidVersionConfig);
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({
        error_msg: 'Configuration validation failed',
        errors: expect.arrayContaining([
          expect.objectContaining({
            resource_type: 'routes',
            error: expect.stringContaining('routes_conf_version must be a number'),
          }),
        ]),
      });
    });

    it('validate config (empty body)', async () => {
      const resp = await clientException.post(VALIDATE_ENDPOINT, '');
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({
        error_msg: 'invalid request body: empty request body',
      });
    });

    it('validate config (invalid YAML)', async () => {
      const resp = await clientException.post(VALIDATE_ENDPOINT, 'invalid: yaml: [', {
        headers: { 'Content-Type': 'application/yaml' },
      });
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({
        error_msg: expect.stringContaining('invalid request body:'),
      });
    });

    it('validate config (duplicate consumer username)', async () => {
      const duplicateConsumerConfig = {
        consumers: [
          {
            username: 'consumer1',
            plugins: {
              'key-auth': {
                key: 'consumer1',
              },
            },
          },
          {
            username: 'consumer1', // Duplicate username
            plugins: {
              'key-auth': {
                key: 'consumer1',
              },
            },
          },
        ],
      };

      const resp = await clientException.post(VALIDATE_ENDPOINT, duplicateConsumerConfig);
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({
        error_msg: 'Configuration validation failed',
        errors: expect.arrayContaining([
          expect.objectContaining({
            resource_type: 'consumers',
            error: expect.stringContaining('found duplicate username consumer1 in consumers'),
          }),
        ]),
      });
    });

    it('validate config (duplicate consumer credential id)', async () => {
      const duplicateCredentialConfig = {
        consumers: [
          {
            username: 'john_1',
          },
          {
            id: 'john_1/credentials/john-a',
            plugins: {
              'key-auth': {
                key: 'auth-a',
              },
            },
          },
          {
            id: 'john_1/credentials/john-a', // Duplicate credential ID
            plugins: {
              'key-auth': {
                key: 'auth-a',
              },
            },
          },
        ],
      };

      const resp = await clientException.post(VALIDATE_ENDPOINT, duplicateCredentialConfig);
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({
        error_msg: 'Configuration validation failed',
        errors: expect.arrayContaining([
          expect.objectContaining({
            resource_type: 'consumers',
            error: expect.stringContaining('found duplicate credential id john_1/credentials/john-a in consumers'),
          }),
        ]),
      });
    });

    it('validate config (invalid plugin)', async () => {
      const resp = await clientException.post(
        VALIDATE_ENDPOINT,
        routeWithUnknownPlugins,
      );
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({
        error_msg: 'Configuration validation failed',
        errors: expect.arrayContaining([
          expect.objectContaining({
            resource_type: 'routes',
            error: expect.stringContaining('unknown plugin [invalid-plugin]'),
          }),
        ]),
      });
    });

    it('validate config (invalid upstream)', async () => {
      const resp = await clientException.post(
        VALIDATE_ENDPOINT,
        routeWithInvalidUpstream,
      );
      expect(resp.status).toEqual(400);
      expect(resp.data).toEqual({
        error_msg: 'Configuration validation failed',
        errors: expect.arrayContaining([
          expect.objectContaining({
            resource_type: 'routes',
            error: expect.stringContaining('failed to match pattern'),
          }),
        ]),
      });
    });
  });
});
