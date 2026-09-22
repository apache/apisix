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
import { describe, expect, it, jest } from '@jest/globals';
import axios from 'axios';
import { readFileSync } from 'node:fs';
import { type IncomingHttpHeaders, request } from 'node:http';
import WS from 'ws';

import { request as requestAdminAPI } from '../ts/admin_api';
import { wait } from '../ts/utils';

// Every test here does at least one real websocket handshake plus etcd sync
// round trip, which the shared 5s Jest default leaves little room for on a
// loaded machine; the handful of tests that need more than this still set
// their own per-test timeout on top of it.
jest.setTimeout(15000);

const PROXY_BASE = 'ws://localhost:1984';
// a loopback address nothing listens on, used as an unreachable upstream node
const DEAD_NODE = '127.0.0.1:1';
const DEAD_NODE_2 = '127.0.0.1:2';
// accepts the connection but never responds, so it reliably exercises the
// "timeout" (504) branch instead of "tcp failure" - unlike an unroutable
// address, this doesn't depend on how a given network treats one
const BLACKHOLE_NODE = '127.0.0.1:1986';
const ECHO_NODE = '127.0.0.1:1980';

let nextRouteId = 1;

// Routes with a URI no other test in this file reuses can just be created
// once and left behind (the whole test-nginx instance goes away at the end
// of the run anyway).
const createRoute = async (
  path: string,
  upstream: object,
  plugins?: object,
) => {
  const id = `ws-proxy-${nextRouteId++}`;
  const res = await requestAdminAPI(`/apisix/admin/routes/${id}`, 'PUT', {
    uri: path,
    upstream,
    plugins,
  });
  expect(res.status).toBeLessThan(300);
  // give etcd -> apisix config sync a moment to land before the first request
  await wait(300);
  return id;
};

// Most tests below share the /websocket_echo URI across very different
// upstream/plugin configs. Deleting and recreating a route under the same
// URI between tests leaves a window where the delete has been sent but
// hasn't synced yet when the next test's create lands, and the two can race
// - the client then gets whichever half-applied state the router held at
// that instant. PUTting the same fixed route id instead is a plain
// overwrite, so there's no delete in flight to race with.
const ECHO_ROUTE_ID = 'ws-proxy-echo';
const putRoute = async (id: string, uri: string, upstream: object, plugins?: object) => {
  const res = await requestAdminAPI(`/apisix/admin/routes/${id}`, 'PUT', {
    uri,
    upstream,
    plugins,
  });
  expect(res.status).toBeLessThan(300);
  await wait(300);
};
const putEchoRoute = (upstream: object, plugins?: object) =>
  putRoute(ECHO_ROUTE_ID, '/websocket_echo', upstream, plugins);
// same idea for the fixture that reports the handshake headers it received
const putHeadersRoute = (upstream: object, plugins?: object) =>
  putRoute('ws-proxy-headers', '/websocket_echo_headers', upstream, plugins);
// and for the fixture whose 127.0.0.1:1981 node refuses the handshake with a 503
const REJECT_ROUTE_ID = 'ws-proxy-reject';
const putRejectRoute = (upstream: object, plugins?: object) =>
  putRoute(REJECT_ROUTE_ID, '/websocket_echo_or_reject', upstream, plugins);

// Opens a websocket connection and resolves with the first frame received,
// without sending anything: for fixtures that speak first.
const receiveFirst = (url: string, protocols?: string[]) =>
  new Promise<{ data: string; protocol: string }>((resolve, reject) => {
    const ws = new WS(url, protocols);
    ws.on('message', (data) => {
      resolve({ data: data.toString(), protocol: ws.protocol });
      ws.close();
    });
    ws.on('error', reject);
  });

// Resolves with the headers of the 101 answer to a handshake that offers the
// given subprotocols. A raw request rather than a WebSocket client, since the
// clients reject a server that selects none of the subprotocols they offered,
// which is exactly the answer some of these cases are about.
const handshakeHeaders = (path: string, protocols: string[]) =>
  new Promise<IncomingHttpHeaders>((resolve, reject) => {
    const req = request({
      host: '127.0.0.1',
      port: 1984,
      path,
      headers: {
        Connection: 'Upgrade',
        Upgrade: 'websocket',
        'Sec-WebSocket-Key': 'dGhlIHNhbXBsZSBub25jZQ==',
        'Sec-WebSocket-Version': '13',
        'Sec-WebSocket-Protocol': protocols.join(', '),
      },
    });
    req.on('upgrade', (res, socket) => {
      socket.destroy();
      resolve(res.headers);
    });
    req.on('response', (res) => reject(new Error(`unexpected status ${res.statusCode}`)));
    req.on('error', reject);
    req.end();
  });

// A plain http upgrade request, for asserting on the status the proxy itself
// answers with when it cannot complete the handshake.
const rawUpgrade = (path: string) =>
  axios.get(`http://127.0.0.1:1984${path}`, {
    headers: {
      Connection: 'Upgrade',
      Upgrade: 'websocket',
      'Sec-WebSocket-Key': 'dGhlIHNhbXBsZSBub25jZQ==',
      'Sec-WebSocket-Version': '13',
    },
    validateStatus: () => true,
  });

// Opens a websocket connection, sends one text frame, resolves with the
// first frame received in reply (or rejects on error/close-before-reply).
const sendAndReceive = (path: string, payload: string) =>
  new Promise<string>((resolve, reject) => {
    const ws = new WebSocket(`${PROXY_BASE}${path}`);
    ws.addEventListener('open', () => ws.send(payload));
    ws.addEventListener('message', (ev) => {
      resolve(ev.data as string);
      ws.close();
    });
    ws.addEventListener('error', (ev) =>
      reject(new Error((ev as unknown as { message?: string }).message ?? 'websocket error')),
    );
  });

// Resolves with the close event's code. onOpen fires right after connecting,
// so it can send a frame or otherwise trigger whatever leads to the close.
//
// The WebSocket spec requires an abnormal closure to fire an error event
// before its close event, not instead of it, so an expected-to-fail
// connection (tolerateError: true) must not treat that error as a failure
// and must instead keep waiting for the close event that follows it.
const waitForClose = (
  path: string,
  onOpen?: (ws: WebSocket) => void,
  tolerateError = false,
) =>
  new Promise<number>((resolve, reject) => {
    const ws = new WebSocket(`${PROXY_BASE}${path}`);
    ws.addEventListener('open', () => onOpen?.(ws));
    ws.addEventListener('close', (ev) => resolve(ev.code));
    ws.addEventListener('error', (ev) => {
      if (!tolerateError) {
        reject(new Error((ev as unknown as { message?: string }).message ?? 'websocket error'));
      }
    });
  });

describe('websocket-proxy (ws/wss upstream scheme)', () => {
  describe('frame-level plugin hooks', () => {
    it('lets a plugin rewrite the client frame before it reaches the upstream, and the upstream frame before it reaches the client', async () => {
      await putEchoRoute(
        { type: 'roundrobin', scheme: 'ws', nodes: { [ECHO_NODE]: 1 } },
        {
          // example-plugin's ws_client_frame/ws_upstream_frame hooks append
          // "-client"/"-upstream" to every text frame they see, in-flight.
          'example-plugin': { i: 1 },
          // the log phase runs once the session is over: report the request
          // type there, which only a websocket session should have set
          'serverless-post-function': {
            phase: 'log',
            functions: [
              'return function(conf, ctx) ngx.log(ngx.WARN, "ws request_type: ", ctx.var.request_type) end',
            ],
          },
        },
      );

      // the echo backend bounces whatever it received back unchanged, so the
      // round trip proves both directions were actually rewritten in flight.
      const reply = await sendAndReceive('/websocket_echo', 'hello');
      expect(reply).toBe('hello-client-upstream');
    });

    it('does not touch binary frames (the hooks only rewrite text frames)', async () => {
      await putEchoRoute(
        { type: 'roundrobin', scheme: 'ws', nodes: { [ECHO_NODE]: 1 } },
        { 'example-plugin': { i: 1 } },
      );

      const reply = await new Promise<ArrayBuffer>((resolve, reject) => {
        const ws = new WebSocket(`${PROXY_BASE}/websocket_echo`);
        ws.binaryType = 'arraybuffer';
        ws.addEventListener('open', () => ws.send(new Uint8Array([1, 2, 3, 4])));
        ws.addEventListener('message', (ev) => {
          resolve(ev.data as ArrayBuffer);
          ws.close();
        });
        ws.addEventListener('error', (ev) =>
          reject(new Error((ev as unknown as { message?: string }).message ?? 'websocket error')),
        );
      });
      expect(new Uint8Array(reply)).toEqual(new Uint8Array([1, 2, 3, 4]));
    });
  });

  describe('fragmented frames', () => {
    it('reassembles a fragmented message into one frame before invoking plugin hooks', async () => {
      await createRoute('/websocket_fragment', {
        type: 'roundrobin',
        scheme: 'ws',
        nodes: { [ECHO_NODE]: 1 },
      }, {
        'example-plugin': { i: 1 },
      });

      // websocket_fragment sends "hello " and "world" as two continuation
      // frames of the same message; if aggregate_fragments works, the client
      // (and the ws_upstream_frame hook in between) see exactly one frame
      // with the joined payload, not two separate ones.
      const messages: string[] = [];
      await new Promise<void>((resolve, reject) => {
        const ws = new WebSocket(`${PROXY_BASE}/websocket_fragment`);
        ws.addEventListener('message', (ev) => {
          messages.push(ev.data as string);
          ws.close();
        });
        ws.addEventListener('close', () => resolve());
        ws.addEventListener('error', (ev) =>
          reject(new Error((ev as unknown as { message?: string }).message ?? 'websocket error')),
        );
      });
      expect(messages).toEqual(['hello world-upstream']);
    });
  });

  describe('ping/pong', () => {
    it('forwards a client ping to the upstream and the upstream pong back to the client', async () => {
      await putEchoRoute({ type: 'roundrobin', scheme: 'ws', nodes: { [ECHO_NODE]: 1 } });

      await new Promise<void>((resolve, reject) => {
        const ws = new WS(`${PROXY_BASE}/websocket_echo`);
        ws.on('open', () => ws.ping());
        ws.on('pong', () => {
          ws.terminate();
          resolve();
        });
        ws.on('error', reject);
      });
    });
  });

  describe('close handshake', () => {
    it('lets the client close cleanly and the upstream echoes the close code back', async () => {
      await putEchoRoute({ type: 'roundrobin', scheme: 'ws', nodes: { [ECHO_NODE]: 1 } });

      const code = await waitForClose('/websocket_echo', (ws) => ws.close(1000, 'bye'));
      expect(code).toBe(1000);
    });

    it('forwards an upstream-initiated close to the client', async () => {
      await createRoute('/websocket_close_upstream_initiated', {
        type: 'roundrobin',
        scheme: 'ws',
        nodes: { [ECHO_NODE]: 1 },
      });

      const code = await waitForClose('/websocket_close_upstream_initiated');
      expect(code).toBe(1000);
    });
  });

  describe('abrupt disconnects', () => {
    it('reports an abnormal closure (1006) to the client when the upstream vanishes mid-session', async () => {
      await createRoute('/websocket_abrupt_close', {
        type: 'roundrobin',
        scheme: 'ws',
        nodes: { [ECHO_NODE]: 1 },
      });

      const code = await waitForClose('/websocket_abrupt_close', (ws) => ws.send('hi'), true);
      expect(code).toBe(1006);
    });

    it('cleans up the upstream side when the client vanishes without closing', async () => {
      await putEchoRoute({ type: 'roundrobin', scheme: 'ws', nodes: { [ECHO_NODE]: 1 } });

      const activeConnections = async () => {
        const res = await axios.get('http://localhost:1984/apisix/nginx_status');
        const match = /Active connections:\s*(\d+)/.exec(res.data as string);
        return match ? Number(match[1]) : NaN;
      };

      const baseline = await activeConnections();

      // open and forcibly kill a handful of connections without a close
      // handshake (ws's .terminate() drops the TCP connection directly,
      // which the standard WebSocket API has no equivalent for)
      for (let i = 0; i < 10; i++) {
        await new Promise<void>((resolve, reject) => {
          const ws = new WS(`${PROXY_BASE}/websocket_echo`);
          ws.on('open', () => {
            ws.terminate();
            resolve();
          });
          ws.on('error', reject);
        });
      }

      // give the proxy's forwarder coroutines a moment to notice the dead
      // sockets and tear themselves down
      await wait(1000);

      const after = await activeConnections();
      // a leak would grow roughly linearly with the number of terminated
      // connections (10 here); allow some slack for unrelated background
      // activity in the shared test-nginx instance instead of an exact match
      expect(after).toBeLessThan(baseline + 5);
    }, 10000);
  });

  describe('upstream retry', () => {
    it('retries the next node when the first one refuses the connection', async () => {
      await putEchoRoute({
        type: 'roundrobin',
        scheme: 'ws',
        retries: 3,
        nodes: { [DEAD_NODE]: 100, [ECHO_NODE]: 1 },
      });

      const reply = await sendAndReceive('/websocket_echo', 'hello');
      expect(reply).toBe('hello');
    });

    it('returns 502 once every node has been tried and failed', async () => {
      await putEchoRoute({
        type: 'roundrobin',
        scheme: 'ws',
        retries: 2,
        nodes: { [DEAD_NODE]: 1, [DEAD_NODE_2]: 1 },
      });

      await expect(
        axios.get('http://localhost:1984/websocket_echo', {
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

    it('retries past a connect timeout, not just a refused connection', async () => {
      await putEchoRoute({
        type: 'roundrobin',
        scheme: 'ws',
        retries: 2,
        timeout: { connect: 1, send: 5, read: 5 },
        nodes: { [BLACKHOLE_NODE]: 100, [ECHO_NODE]: 1 },
      });

      const start = Date.now();
      const reply = await sendAndReceive('/websocket_echo', 'hello');
      const elapsed = Date.now() - start;
      expect(reply).toBe('hello');
      // an instant refusal (tcp_failure) would resolve in a few ms; only a
      // real connect timeout takes close to the configured 1s
      expect(elapsed).toBeGreaterThanOrEqual(900);
    }, 10000);

    it('retries across more than one dead node before reaching a healthy one', async () => {
      await putEchoRoute({
        type: 'roundrobin',
        scheme: 'ws',
        retries: 3,
        nodes: { [DEAD_NODE]: 100, [DEAD_NODE_2]: 100, [ECHO_NODE]: 1 },
      });

      const reply = await sendAndReceive('/websocket_echo', 'hello');
      expect(reply).toBe('hello');
    });

    it('retries the same way for a least_conn upstream, not just roundrobin', async () => {
      await putEchoRoute({
        type: 'least_conn',
        scheme: 'ws',
        retries: 3,
        nodes: { [DEAD_NODE]: 100, [ECHO_NODE]: 1 },
      });

      const reply = await sendAndReceive('/websocket_echo', 'hello');
      expect(reply).toBe('hello');
    });
  });

  describe('passive health check', () => {
    it('marks a node unhealthy after it answers the handshake with a failing status', async () => {
      // 127.0.0.1:1981 accepts TCP connections but answers every handshake with
      // a 503 (see websocket_echo_or_reject), so the active tcp check below can
      // never flag it on its own: only the passive http status report the proxy
      // makes for the non-101 response can move it to unhealthy.
      await putRejectRoute({
        type: 'roundrobin',
        scheme: 'ws',
        retries: 1,
        nodes: { '127.0.0.1:1981': 1, [ECHO_NODE]: 1 },
        checks: {
          // probes only once at startup and then stay out of the way, so they can
          // neither flag the node unhealthy nor flip it back to healthy again
          active: {
            type: 'tcp',
            host: '127.0.0.1',
            timeout: 1,
            healthy: { interval: 3600 },
            unhealthy: { interval: 3600 },
          },
          passive: { unhealthy: { http_statuses: [503], http_failures: 1 } },
        },
      });

      let unhealthyFound = false;
      for (let i = 0; i < 10 && !unhealthyFound; i++) {
        // each request may or may not pick the 503 node first; the retry makes
        // it succeed either way, and a pick of that node reports the failure
        expect(await sendAndReceive('/websocket_echo_or_reject', 'hello')).toBe('hello');
        await wait(500);
        const res = await requestAdminAPI(`/v1/healthcheck/routes/${REJECT_ROUTE_ID}`);
        const { nodes } = res.data as { nodes: { port: number; status: string }[] };
        unhealthyFound = nodes.some((n) => n.port === 1981 && n.status !== 'healthy');
      }

      expect(unhealthyFound).toBe(true);
    }, 30000);
  });

  describe('upstream URI forwarding', () => {
    it("forwards the client's request URI, including the query string", async () => {
      await createRoute('/websocket_echo_uri', {
        type: 'roundrobin',
        scheme: 'ws',
        nodes: { [ECHO_NODE]: 1 },
      });

      const reply = await new Promise<string>((resolve, reject) => {
        const ws = new WebSocket(`${PROXY_BASE}/websocket_echo_uri?foo=bar`);
        ws.addEventListener('message', (ev) => {
          resolve(ev.data as string);
          ws.close();
        });
        ws.addEventListener('error', (ev) =>
          reject(new Error((ev as unknown as { message?: string }).message ?? 'websocket error')),
        );
      });
      expect(reply).toBe('/websocket_echo_uri?foo=bar');
    });

    it("forwards the proxy-rewrite plugin's rewritten URI instead of the original one", async () => {
      await createRoute(
        '/websocket_proxy_rewrite_uri',
        {
          type: 'roundrobin',
          scheme: 'ws',
          nodes: { [ECHO_NODE]: 1 },
        },
        {
          'proxy-rewrite': { uri: '/websocket_echo_uri' },
        },
      );

      const reply = await new Promise<string>((resolve, reject) => {
        const ws = new WebSocket(`${PROXY_BASE}/websocket_proxy_rewrite_uri`);
        ws.addEventListener('message', (ev) => {
          resolve(ev.data as string);
          ws.close();
        });
        ws.addEventListener('error', (ev) =>
          reject(new Error((ev as unknown as { message?: string }).message ?? 'websocket error')),
        );
      });
      expect(reply).toBe('/websocket_echo_uri');
    });
  });

  describe('client address headers', () => {
    it('overrides X-Real-IP and appends this hop to X-Forwarded-For, not what the client sent', async () => {
      await putHeadersRoute({
        type: 'roundrobin',
        scheme: 'ws',
        nodes: { [ECHO_NODE]: 1 },
      });

      // connect via the literal loopback address, not PROXY_BASE's
      // "localhost", so $remote_addr is deterministically 127.0.0.1
      const reply = await new Promise<string>((resolve, reject) => {
        const ws = new WS('ws://127.0.0.1:1984/websocket_echo_headers', {
          headers: { 'X-Real-IP': '1.2.3.4', 'X-Forwarded-For': '5.6.7.8' },
        });
        ws.on('message', (data) => {
          resolve(data.toString());
          ws.close();
        });
        ws.on('error', reject);
      });

      const seen = JSON.parse(reply);
      expect(seen.x_real_ip).toBe('127.0.0.1');
      expect(seen.x_forwarded_for).toBe('5.6.7.8, 127.0.0.1');
    });
  });

  describe('upstream Host header', () => {
    it('honors the host set by proxy-rewrite on the upstream handshake', async () => {
      await putHeadersRoute(
        { type: 'roundrobin', scheme: 'ws', nodes: { [ECHO_NODE]: 1 } },
        { 'proxy-rewrite': { host: 'rewritten.example.com' } },
      );

      const { data } = await receiveFirst('ws://127.0.0.1:1984/websocket_echo_headers');
      expect(JSON.parse(data).host).toBe('rewritten.example.com');
    });

    it("sends the retried node's own host with pass_host: node", async () => {
      await putHeadersRoute({
        type: 'roundrobin',
        scheme: 'ws',
        pass_host: 'node',
        retries: 1,
        nodes: { [DEAD_NODE]: 100, [ECHO_NODE]: 1 },
      });

      const { data } = await receiveFirst('ws://127.0.0.1:1984/websocket_echo_headers');
      expect(JSON.parse(data).host).toBe(ECHO_NODE);
    });
  });

  describe('wss upstream', () => {
    // the fake server's TLS listener; its certificate is issued for test.com
    const TLS_NODE = '127.0.0.1:1983';

    it('proxies over TLS with certificate verification off', async () => {
      await putHeadersRoute({
        type: 'roundrobin',
        scheme: 'wss',
        tls: { verify: false },
        nodes: { [TLS_NODE]: 1 },
      });

      const { data } = await receiveFirst('ws://127.0.0.1:1984/websocket_echo_headers');
      expect(JSON.parse(data).host).toBe('127.0.0.1:1984');
    });

    it('verifies the certificate against the upstream host, port excluded', async () => {
      await putHeadersRoute({
        type: 'roundrobin',
        scheme: 'wss',
        pass_host: 'rewrite',
        upstream_host: 'test.com:1983',
        tls: { verify: true },
        nodes: { [TLS_NODE]: 1 },
      });

      const { data } = await receiveFirst('ws://127.0.0.1:1984/websocket_echo_headers');
      expect(JSON.parse(data).host).toBe('test.com:1983');
    });

    it('refuses an upstream whose certificate does not match the host', async () => {
      await putHeadersRoute({
        type: 'roundrobin',
        scheme: 'wss',
        tls: { verify: true },
        nodes: { [TLS_NODE]: 1 },
      });

      const res = await rawUpgrade('/websocket_echo_headers');
      expect(res.status).toBe(502);
    });

    it('rejects tls.ca_certs, which the ws/wss client cannot apply', async () => {
      const cert = readFileSync(new URL('../certs/apisix.crt', import.meta.url), 'utf8');
      const res = await requestAdminAPI(
        '/apisix/admin/upstreams/ws-proxy-ca-certs',
        'PUT',
        {
          type: 'roundrobin',
          scheme: 'wss',
          tls: { verify: true, ca_certs: [cert] },
          nodes: { [TLS_NODE]: 1 },
        },
        undefined,
        { validateStatus: () => true },
      );
      expect(res.status).toBe(400);
    });
  });

  describe('subprotocol negotiation', () => {
    it('answers the client with the subprotocol the upstream selected', async () => {
      await createRoute('/websocket_subprotocol', {
        type: 'roundrobin',
        scheme: 'ws',
        nodes: { [ECHO_NODE]: 1 },
      });

      const headers = await handshakeHeaders('/websocket_subprotocol?select=chat', [
        'other',
        'chat',
      ]);
      expect(headers['sec-websocket-protocol']).toBe('chat');
    });

    it('answers with no subprotocol when the upstream selected none', async () => {
      // echoing the client's whole offer back instead would announce
      // subprotocols the upstream never agreed to
      const headers = await handshakeHeaders('/websocket_subprotocol?select=none', [
        'other',
        'chat',
      ]);
      expect(headers['sec-websocket-protocol']).toBeUndefined();
    });
  });

  describe('traffic-split', () => {
    it('proxies frames through a ws upstream chosen by traffic-split', async () => {
      // the route's own upstream is plain http: only the traffic-split pick is ws
      await putEchoRoute(
        { type: 'roundrobin', scheme: 'http', nodes: { [ECHO_NODE]: 1 } },
        {
          'traffic-split': {
            rules: [
              {
                weighted_upstreams: [
                  {
                    upstream: {
                      type: 'roundrobin',
                      scheme: 'ws',
                      nodes: { [ECHO_NODE]: 1 },
                    },
                    weight: 1,
                  },
                ],
              },
            ],
          },
        },
      );

      expect(await sendAndReceive('/websocket_echo', 'hello')).toBe('hello');
    });
  });

  describe('upstream retry after a non-101 handshake', () => {
    it('retries the next node and completes the session on it', async () => {
      // 127.0.0.1:1981 answers the handshake with a 503 (websocket_echo_or_reject)
      await putRejectRoute({
        type: 'roundrobin',
        scheme: 'ws',
        retries: 1,
        nodes: { '127.0.0.1:1981': 100, [ECHO_NODE]: 1 },
      });

      expect(await sendAndReceive('/websocket_echo_or_reject', 'hello')).toBe('hello');
    });
  });

  describe('frame size (websocket-proxy plugin)', () => {
    it('closes the connection on a single frame over the 65535-byte default', async () => {
      await putEchoRoute({
        type: 'roundrobin',
        scheme: 'ws',
        nodes: { [ECHO_NODE]: 1 },
      });

      const code = await waitForClose(
        '/websocket_echo',
        (ws) => ws.send('x'.repeat(70000)),
        true,
      );
      expect(code).toBe(1006);
    }, 10000);

    it('forwards a >64K frame in each direction once websocket-proxy raises max_payload_len', async () => {
      await createRoute(
        '/websocket_echo_large',
        {
          type: 'roundrobin',
          scheme: 'ws',
          nodes: { [ECHO_NODE]: 1 },
        },
        {
          'websocket-proxy': {
            client_max_payload_len: 2 * 1024 * 1024,
            upstream_max_payload_len: 2 * 1024 * 1024,
          },
        },
      );

      const payload = 'x'.repeat(1024 * 1024);
      const reply = await sendAndReceive('/websocket_echo_large', payload);
      expect(reply).toBe(payload);
    }, 15000);

    it('relays a >64K client message once only client_max_payload_len is raised, with no reply raised', async () => {
      // websocket_ack_large replies with a short "received:<n>" ack instead
      // of echoing, so this only exercises the client-to-upstream direction:
      // it would still pass even if the (unconfigured) reply-out-to-client
      // send limit were wrongly stuck at the default.
      await createRoute(
        '/websocket_ack_large',
        {
          type: 'roundrobin',
          scheme: 'ws',
          nodes: { [ECHO_NODE]: 1 },
        },
        {
          'websocket-proxy': { client_max_payload_len: 2 * 1024 * 1024 },
        },
      );

      const payload = 'x'.repeat(200000);
      const reply = await sendAndReceive('/websocket_ack_large', payload);
      expect(reply).toBe(`received:${payload.length}`);
    }, 15000);

    it('relays a >64K upstream push once only upstream_max_payload_len is raised, with no client message sent', async () => {
      // websocket_send_large pushes a 1MiB frame unprompted right after the
      // handshake; only the upstream-to-client direction needs raising here,
      // so this catches a fix that raised the client's own receive limit
      // (irrelevant, nothing large is sent to it) instead of its send limit.
      await createRoute(
        '/websocket_send_large',
        {
          type: 'roundrobin',
          scheme: 'ws',
          nodes: { [ECHO_NODE]: 1 },
        },
        {
          'websocket-proxy': { upstream_max_payload_len: 2 * 1024 * 1024 },
        },
      );

      const reply = await new Promise<string>((resolve, reject) => {
        const ws = new WebSocket(`${PROXY_BASE}/websocket_send_large`);
        ws.addEventListener('message', (ev) => {
          resolve(ev.data as string);
          ws.close();
        });
        ws.addEventListener('error', (ev) =>
          reject(new Error((ev as unknown as { message?: string }).message ?? 'websocket error')),
        );
      });
      expect(reply).toBe('x'.repeat(1024 * 1024));
    }, 15000);

    it('lets the larger of two asymmetric limits govern its own direction, not the smaller one', async () => {
      // client_max_payload_len (100000) is smaller than the 1MiB push below,
      // upstream_max_payload_len (2MiB) is larger: the push must still get
      // through on the strength of the upstream-side limit alone, proving
      // the two directions are not tied to the same configured value.
      await createRoute(
        '/websocket_send_large_asymmetric',
        {
          type: 'roundrobin',
          scheme: 'ws',
          nodes: { [ECHO_NODE]: 1 },
        },
        {
          'websocket-proxy': {
            client_max_payload_len: 100000,
            upstream_max_payload_len: 2 * 1024 * 1024,
          },
          // the fixture is dispatched by URI (see t/lib/server.lua's go()),
          // so rewrite this route's distinct client-facing path back to the
          // websocket_send_large fixture the previous test already uses
          'proxy-rewrite': { uri: '/websocket_send_large' },
        },
      );

      const reply = await new Promise<string>((resolve, reject) => {
        const ws = new WebSocket(`${PROXY_BASE}/websocket_send_large_asymmetric`);
        ws.addEventListener('message', (ev) => {
          resolve(ev.data as string);
          ws.close();
        });
        ws.addEventListener('error', (ev) =>
          reject(new Error((ev as unknown as { message?: string }).message ?? 'websocket error')),
        );
      });
      expect(reply).toBe('x'.repeat(1024 * 1024));
    }, 15000);

    it('rejects a payload len beyond the library\'s 2147483647 (2^31 - 1) frame length limit', async () => {
      const res = await requestAdminAPI(
        '/apisix/admin/routes/ws-proxy-oversized-limit',
        'PUT',
        {
          uri: '/websocket_echo_large',
          upstream: {
            type: 'roundrobin',
            scheme: 'ws',
            nodes: { [ECHO_NODE]: 1 },
          },
          plugins: {
            'websocket-proxy': { client_max_payload_len: 2147483648 },
          },
        },
        undefined,
        { validateStatus: () => true },
      );
      expect(res.status).toBe(400);
    });
  });

  describe('concurrent connections', () => {
    it("keeps two simultaneous connections' frame data isolated from each other", async () => {
      await putEchoRoute(
        { type: 'roundrobin', scheme: 'ws', nodes: { [ECHO_NODE]: 1 } },
        { 'example-plugin': { i: 1 } },
      );

      const open = (payload: string) =>
        new Promise<string>((resolve, reject) => {
          const ws = new WebSocket(`${PROXY_BASE}/websocket_echo`);
          ws.addEventListener('open', () => ws.send(payload));
          ws.addEventListener('message', (ev) => {
            resolve(ev.data as string);
            ws.close();
          });
          ws.addEventListener('error', (ev) =>
            reject(new Error((ev as unknown as { message?: string }).message ?? 'websocket error')),
          );
        });

      const [replyA, replyB] = await Promise.all([open('alpha'), open('beta')]);
      expect(replyA).toBe('alpha-client-upstream');
      expect(replyB).toBe('beta-client-upstream');
    });
  });
});
