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
import { generateKeyPair } from 'node:crypto';
import { existsSync } from 'node:fs';
import { readFile, rm, writeFile } from 'node:fs/promises';
import { promisify } from 'node:util';

import { afterAll, beforeAll, describe, expect, it } from '@jest/globals';
import axios from 'axios';
import * as compose from 'docker-compose';
import { gql, request } from 'graphql-request';
import { Api as LagoApi, Client as LagoClient } from 'lago-javascript-client';
import simpleGit from 'simple-git';
import * as YAML from 'yaml';

import { request as requestAdminAPI } from '../ts/admin_api';
import { wait } from '../ts/utils';

const LAGO_VERSION = 'v1.27.0';
const LAGO_PATH = '/tmp/lago';
const LAGO_FRONT_PORT = 59999;
const LAGO_API_PORT = 30699;
const LAGO_API_URL = `http://127.0.0.1:${LAGO_API_PORT}`;
const LAGO_API_BASEURL = `http://127.0.0.1:${LAGO_API_PORT}/api/v1`;
const LAGO_API_GRAPHQL_ENDPOINT = `${LAGO_API_URL}/graphql`;
const LAGO_BILLABLE_METRIC_CODE = 'test';
const LAGO_EXTERNAL_SUBSCRIPTION_ID = 'jack_test';

// The project uses AGPLv3, so we can't store the docker compose file it uses in our repository and download it during testing.
const downloadComposeFile = async () =>
  simpleGit().clone('https://github.com/getlago/lago', LAGO_PATH, {
    '--depth': '1',
    '--branch': LAGO_VERSION,
  });

const launchLago = async () => {
  // patch docker-compose.yml to disable useless port
  const composeFilePath = `${LAGO_PATH}/docker-compose.yml`;
  const composeFile = YAML.parse(await readFile(composeFilePath, 'utf8'));
  delete composeFile.services.front; // front-end is not needed for tests
  delete composeFile.services['api-clock']; // clock is not needed for tests
  delete composeFile.services['api-worker']; // worker is not needed for tests
  delete composeFile.services['pdf']; // pdf is not needed for tests
  delete composeFile.services.redis.ports; // prevent port conflict
  delete composeFile.services.db.ports; // prevent port conflict
  await writeFile(composeFilePath, YAML.stringify(composeFile), 'utf8');

  // launch services
  const { privateKey } = await promisify(generateKeyPair)('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'pkcs1', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs1', format: 'pem' },
  });
  const composeOpts: compose.IDockerComposeOptions = {
    cwd: LAGO_PATH,
    log: true,
    env: {
      LAGO_RSA_PRIVATE_KEY: Buffer.from(privateKey).toString('base64'),
      FRONT_PORT: `${LAGO_FRONT_PORT}`, // avoiding conflicts, tests do not require a front-end
      API_PORT: `${LAGO_API_PORT}`,
      LAGO_FRONT_URL: `http://127.0.0.1:${LAGO_FRONT_PORT}`,
      LAGO_API_URL,
    },
  };

  await compose.createAll(composeOpts);
  await compose.upOne('api', composeOpts);
  await compose.exec('api', 'rails db:create', composeOpts);
  await compose.exec('api', 'rails db:migrate', composeOpts);
  await compose.upAll(composeOpts);
};

const provisionLago = async () => {
  // sign up
  const { registerUser } = await request<{
    registerUser: { token: string; user: { organizations: { id: string } } };
  }>(
    LAGO_API_GRAPHQL_ENDPOINT,
    gql`
      mutation signup($input: RegisterUserInput!) {
        registerUser(input: $input) {
          token
          user {
            id
            organizations {
              id
            }
          }
        }
      }
    `,
    {
      input: {
        email: 'test@test.com',
        password: 'Admin000!',
        organizationName: 'test',
      },
    },
  );

  const webToken = registerUser.token;
  const organizationId = registerUser.user.organizations[0].id;
  const requestHeaders = {
    Authorization: `Bearer ${webToken}`,
    'X-Lago-Organization': organizationId,
  };

  // list api keys
  const { apiKeys } = await request<{
    apiKeys: { collection: { id: string }[] };
  }>(
    LAGO_API_GRAPHQL_ENDPOINT,
    gql`
      query getApiKeys {
        apiKeys(page: 1, limit: 20) {
          collection {
            id
          }
        }
      }
    `,
    {},
    requestHeaders,
  );

  // get first api key
  const { apiKey } = await request<{ apiKey: { value: string } }>(
    LAGO_API_GRAPHQL_ENDPOINT,
    gql`
      query getApiKeyValue($id: ID!) {
        apiKey(id: $id) {
          id
          value
        }
      }
    `,
    { id: apiKeys.collection[0].id },
    requestHeaders,
  );

  const lagoClient = LagoClient(apiKey.value, { baseUrl: LAGO_API_BASEURL });

  // create billable metric
  const { data: billableMetric } =
    await lagoClient.billableMetrics.createBillableMetric({
      billable_metric: {
        name: LAGO_BILLABLE_METRIC_CODE,
        code: LAGO_BILLABLE_METRIC_CODE,
        aggregation_type: 'count_agg',
        filters: [
          {
            key: 'tier',
            values: ['normal', 'expensive'],
          },
        ],
      },
    });

  // create plan
  const { data: plan } = await lagoClient.plans.createPlan({
    plan: {
      name: 'test',
      code: 'test',
      interval: 'monthly',
      amount_cents: 0,
      amount_currency: 'USD',
      pay_in_advance: false,
      charges: [
        {
          billable_metric_id: billableMetric.billable_metric.lago_id,
          charge_model: 'standard',
          pay_in_advance: false,
          properties: { amount: '1' },
          filters: [
            {
              properties: { amount: '10' },
              values: { tier: ['expensive'] },
            },
          ],
        },
      ],
    },
  });

  // create customer
  const external_customer_id = 'jack';
  const { data: customer } = await lagoClient.customers.createCustomer({
    customer: {
      external_id: external_customer_id,
      name: 'Jack',
      currency: 'USD',
    },
  });

  // assign plan to customer
  await lagoClient.subscriptions.createSubscription({
    subscription: {
      external_customer_id: customer.customer.external_id,
      plan_code: plan.plan.code,
      external_id: LAGO_EXTERNAL_SUBSCRIPTION_ID,
    },
  });

  return { apiKey: apiKey.value, client: lagoClient };
};

describe('Plugin - Lago', () => {
  const JACK_USERNAME = 'jack_test';
  const client = axios.create({ baseURL: 'http://127.0.0.1:1984' });

  let restAPIKey: string;
  let lagoClient: LagoApi<unknown>; // prettier-ignore

  // set up
  beforeAll(async () => {
    if (existsSync(LAGO_PATH)) await rm(LAGO_PATH, { recursive: true });
    await downloadComposeFile();
    await launchLago();
    let res = await provisionLago();
    restAPIKey = res.apiKey;
    lagoClient = res.client;
  }, 120 * 1000);

  // clean up
  afterAll(async () => {
    await compose.downAll({
      cwd: LAGO_PATH,
      commandOptions: ['--volumes'],
    });
    await rm(LAGO_PATH, { recursive: true });
  }, 30 * 1000);

  it('should create route', async () => {
    await expect(
      requestAdminAPI('/apisix/admin/routes/1', 'PUT', {
        uri: '/hello',
        upstream: {
          nodes: {
            '127.0.0.1:1980': 1,
          },
          type: 'roundrobin',
        },
        plugins: {
          'request-id': { include_in_response: true }, // for transaction_id
          'key-auth': {}, // for subscription_id
          lago: {
            endpoint_addrs: [LAGO_API_URL],
            token: restAPIKey,
            event_transaction_id: '${http_x_request_id}',
            event_subscription_id: '${http_x_consumer_username}',
            event_code: 'test',
            batch_max_size: 1, // does not buffered usage reports
          },
        },
      }),
    ).resolves.not.toThrow();

    await expect(
      requestAdminAPI('/apisix/admin/routes/2', 'PUT', {
        uri: '/hello1',
        upstream: {
          nodes: {
            '127.0.0.1:1980': 1,
          },
          type: 'roundrobin',
        },
        plugins: {
          'request-id': { include_in_response: true },
          'key-auth': {},
          lago: {
            endpoint_addrs: [LAGO_API_URL],
            token: restAPIKey,
            event_transaction_id: '${http_x_request_id}',
            event_subscription_id: '${http_x_consumer_username}',
            event_code: 'test',
            event_properties: { tier: 'expensive' },
            batch_max_size: 1,
          },
        },
      }),
    ).resolves.not.toThrow();
  });

  it('should create consumer', async () =>
    expect(
      requestAdminAPI(`/apisix/admin/consumers/${JACK_USERNAME}`, 'PUT', {
        username: JACK_USERNAME,
        plugins: {
          'key-auth': { key: JACK_USERNAME },
        },
      }),
    ).resolves.not.toThrow());

  it('call API (without key)', async () => {
    const res = await client.get('/hello', { validateStatus: () => true });
    expect(res.status).toEqual(401);
  });

  it('call normal API', async () => {
    for (let i = 0; i < 3; i++) {
      await expect(
        client.get('/hello', { headers: { apikey: JACK_USERNAME } }),
      ).resolves.not.toThrow();
    }
    await wait(500);
  });

  it('check Lago events (normal API)', async () => {
    const { data } = await lagoClient.events.findAllEvents({
      external_subscription_id: LAGO_EXTERNAL_SUBSCRIPTION_ID,
    });

    expect(data.events).toHaveLength(3);
    expect(data.events[0].code).toEqual(LAGO_BILLABLE_METRIC_CODE);
  });

  let expensiveStartAt: Date;
  it('call expensive API', async () => {
    expensiveStartAt = new Date();
    for (let i = 0; i < 3; i++) {
      await expect(
        client.get('/hello1', { headers: { apikey: JACK_USERNAME } }),
      ).resolves.not.toThrow();
    }
    await wait(500);
  });

  it('check Lago events (expensive API)', async () => {
    const { data } = await lagoClient.events.findAllEvents({
      external_subscription_id: LAGO_EXTERNAL_SUBSCRIPTION_ID,
      timestamp_from: expensiveStartAt.toISOString(),
    });

    expect(data.events).toHaveLength(3);
    expect(data.events[0].code).toEqual(LAGO_BILLABLE_METRIC_CODE);
    expect(data.events[1].properties).toEqual({ tier: 'expensive' });
  });
});
