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
import { afterAll, afterEach, beforeAll, describe, expect, it } from '@jest/globals';
import axios from 'axios';

import { request as requestAdminAPI } from '../ts/admin_api';
import { wait } from '../ts/utils';

const PROXY_BASE = 'ws://localhost:1984';
const ROUTE_URI = '/websocket_echo';
const DEAD_NODE = '127.0.0.1:1';
const ECHO_NODE = '127.0.0.1:1980';

let nextRouteId = 1;

// Every route this suite creates is torn down in afterEach, so a failed
// assertion in one test never leaves state for the next one to trip over.
const createdRouteIds: string[] = [];

const createRoute = async (upstream: object, plugins?: object) => {
  const id = `ws-enhanced-${nextRouteId++}`;
  const res = await requestAdminAPI(`/apisix/admin/routes/${id}`, 'PUT', {
    uri: ROUTE_URI,
    upstream,
    plugins,
  });
  expect(res.status).toBe(res.status < 300 ? res.status : 200);
  createdRouteIds.push(id);
  // give etcd -> apisix config sync a moment to land before the first request
  await wait(300);
  return id;
};

afterEach(async () => {
  while (createdRouteIds.length > 0) {
    const id = createdRouteIds.pop();
    await requestAdminAPI(`/apisix/admin/routes/${id}`, 'DELETE');
  }
});

// Opens a websocket connection, sends one text frame, resolves with the
// first frame received in reply (or rejects on error/close-before-reply).
const sendAndReceive = (payload: string) =>
  new Promise<string>((resolve, reject) => {
    const ws = new WebSocket(`${PROXY_BASE}${ROUTE_URI}`);
    ws.addEventListener('open', () => ws.send(payload));
    ws.addEventListener('message', (ev) => {
      resolve(ev.data as string);
      ws.close();
    });
    ws.addEventListener('error', (ev) =>
      reject(new Error((ev as unknown as { message?: string }).message ?? 'websocket error')),
    );
  });

describe('websocket-enhanced (ws/wss upstream scheme)', () => {
  describe('frame-level plugin hooks', () => {
    beforeAll(() =>
      createRoute(
        {
          type: 'roundrobin',
          scheme: 'ws',
          nodes: { [ECHO_NODE]: 1 },
        },
        {
          // example-plugin's ws_client_frame/ws_upstream_frame hooks append
          // "-client"/"-upstream" to every text frame they see, in-flight.
          'example-plugin': { i: 1 },
        },
      ),
    );

    it('lets a plugin rewrite the client frame before it reaches the upstream, and the upstream frame before it reaches the client', async () => {
      // the echo backend bounces whatever it received back unchanged, so the
      // round trip proves both directions were actually rewritten in flight.
      const reply = await sendAndReceive('hello');
      expect(reply).toBe('hello-client-upstream');
    });
  });

  describe('upstream retry', () => {
    it('retries the next node when the first one refuses the connection', async () => {
      await createRoute({
        type: 'roundrobin',
        scheme: 'ws',
        retries: 3,
        nodes: { [DEAD_NODE]: 100, [ECHO_NODE]: 1 },
      });

      const reply = await sendAndReceive('hello');
      expect(reply).toBe('hello');
    });

    it('returns 502 once every node has been tried and failed', async () => {
      await createRoute({
        type: 'roundrobin',
        scheme: 'ws',
        retries: 2,
        nodes: { [DEAD_NODE]: 1, '127.0.0.1:2': 1 },
      });

      await expect(
        axios.get(`http://localhost:1984${ROUTE_URI}`, {
          headers: {
            Connection: 'Upgrade',
            Upgrade: 'websocket',
            'Sec-WebSocket-Key': 'dGhlIHNhbXBsZSBub25jZQ==',
            'Sec-WebSocket-Version': '13',
          },
        }),
      ).rejects.toMatchObject({
        response: { status: 502 },
      });
    });
  });
});
