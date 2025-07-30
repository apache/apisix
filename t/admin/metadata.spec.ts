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
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

import { request as requestAdminAPI } from '../ts/admin_api';

describe('Resource Metadata', () => {
  describe('Consumer', () => {
    it('should ensure additionalProperties is false', () =>
      expect(
        requestAdminAPI(
          '/apisix/admin/consumers/jack',
          'PUT',
          {
            username: 'jack',
            invalid: true,
          },
          undefined,
          { validateStatus: () => true },
        ),
      ).resolves.toMatchObject({ status: 400 }));

    it('should accept desc field', () =>
      expect(
        requestAdminAPI('/apisix/admin/consumers/jack', 'PUT', {
          username: 'jack',
          desc: 'test_desc',
        }),
      ).resolves.not.toThrow());
  });

  describe('Consumer Credentials', () => {
    it('should ensure additionalProperties is false', () =>
      expect(
        requestAdminAPI(
          '/apisix/admin/consumers/jack/credentials/cred1',
          'PUT',
          {
            plugins: { 'key-auth': { key: 'test' } },
            invalid: true,
          },
          undefined,
          { validateStatus: () => true },
        ),
      ).resolves.toMatchObject({ status: 400 }));

    it('should accept name field', () =>
      expect(
        requestAdminAPI(
          '/apisix/admin/consumers/jack/credentials/cred1',
          'PUT',
          {
            name: 'test_name',
            plugins: { 'key-auth': { key: 'test' } },
          },
        ),
      ).resolves.not.toThrow());
  });

  describe('SSL', () => {
    const path = resolve(__dirname, '../certs/');
    let cert: string;
    let key: string;

    beforeAll(async () => {
      cert = await readFile(resolve(path, 'apisix.crt'), 'utf-8');
      key = await readFile(resolve(path, 'apisix.key'), 'utf-8');
    });

    it('should ensure additionalProperties is false', () =>
      expect(
        requestAdminAPI(
          '/apisix/admin/ssls/ssl1',
          'PUT',
          { sni: 'test.com', cert, key, invalid: true },
          undefined,
          { validateStatus: () => true },
        ),
      ).resolves.toMatchObject({ status: 400 }));

    it('should accept desc field', () =>
      expect(
        requestAdminAPI('/apisix/admin/ssls/ssl1', 'PUT', {
          desc: 'test_desc',
          sni: 'test.com',
          cert,
          key,
        }),
      ).resolves.not.toThrow());
  });

  describe('Proto', () => {
    it('should ensure additionalProperties is false', () =>
      expect(
        requestAdminAPI(
          '/apisix/admin/protos/proto1',
          'PUT',
          { content: 'syntax = "proto3";', invalid: true },
          undefined,
          { validateStatus: () => true },
        ),
      ).resolves.toMatchObject({ status: 400 }));

    it('should accept name/labels field', () =>
      expect(
        requestAdminAPI('/apisix/admin/protos/proto1', 'PUT', {
          name: 'test_name',
          labels: { test: 'test' },
          content: 'syntax = "proto3";',
        }),
      ).resolves.not.toThrow());
  });

  describe('Stream Route', () => {
    it('should ensure additionalProperties is false', () =>
      expect(
        requestAdminAPI(
          '/apisix/admin/stream_routes/sr1',
          'PUT',
          { upstream: { nodes: { '127.0.0.1:5432': 1 } }, invalid: true },
          undefined,
          { validateStatus: () => true },
        ),
      ).resolves.toMatchObject({ status: 400 }));

    it('should accept name field', () =>
      expect(
        requestAdminAPI('/apisix/admin/stream_routes/sr1', 'PUT', {
          name: 'test_name',
          upstream: { nodes: { '127.0.0.1:5432': 1 } },
        }),
      ).resolves.not.toThrow());
  });

  describe('Consumer Group', () => {
    it('should ensure additionalProperties is false', () =>
      expect(
        requestAdminAPI(
          '/apisix/admin/consumer_groups/cg1',
          'PUT',
          { plugins: {}, invalid: true },
          undefined,
          { validateStatus: () => true },
        ),
      ).resolves.toMatchObject({ status: 400 }));

    it('should accept name field', () =>
      expect(
        requestAdminAPI('/apisix/admin/consumer_groups/cg1', 'PUT', {
          name: 'test_name',
          plugins: {},
        }),
      ).resolves.not.toThrow());
  });
});
