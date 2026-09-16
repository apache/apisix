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

/*
 * Drives the gateway's in-process MCP server with the official client SDK.
 *
 * Hand-written curl assertions can only cover the cases we thought of. The SDK
 * parses every response through its own zod schemas and runs the real handshake,
 * so a protocol deviation fails here even when nobody predicted it -- which is
 * the point, now that the protocol layer is our own Lua rather than the SDK's
 * server half.
 */
import { afterEach, describe, expect, it } from '@jest/globals';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { SSEClientTransport } from '@modelcontextprotocol/sdk/client/sse.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';

const STREAMABLE_ENDPOINT = new URL('http://localhost:1984/mcp-interop-http');
const SSE_ENDPOINT = new URL('http://localhost:1984/mcp-interop-sse');

const newClient = () =>
  new Client({ name: 'openapi-to-mcp-interop', version: '1.0.0' });

describe.each([
  ['streamable_http', () => new StreamableHTTPClientTransport(STREAMABLE_ENDPOINT)],
  ['sse', () => new SSEClientTransport(SSE_ENDPOINT)],
])('MCP interop over %s', (_name, makeTransport) => {
  let client: Client | undefined;

  afterEach(async () => {
    await client?.close();
    client = undefined;
  });

  const connected = async () => {
    client = newClient();
    await client.connect(makeTransport());
    return client;
  };

  it('completes the initialize handshake', async () => {
    const c = await connected();
    const version = c.getServerVersion();
    expect(version).toEqual({ name: expect.any(String), version: '0.0.1' });
    expect(c.getServerCapabilities()).toHaveProperty('tools');
  });

  it('lists tools the SDK can parse', async () => {
    const c = await connected();
    const { tools } = await c.listTools();

    expect(tools.length).toBeGreaterThan(0);
    const getPet = tools.find((t) => t.name === 'getPet');
    expect(getPet).toBeDefined();
    expect(getPet!.description).toBe('Get a pet');
    expect(getPet!.inputSchema.type).toBe('object');
    expect(Object.keys(getPet!.inputSchema.properties ?? {})).toEqual(
      expect.arrayContaining(['pathParameters', 'queryParameters']),
    );
  });

  it('calls a tool and returns text content', async () => {
    const c = await connected();
    const result = await c.callTool({
      name: 'getPet',
      arguments: { pathParameters: { petId: 7 } },
    });

    expect(result.isError).toBeFalsy();
    const content = result.content as Array<{ type: string; text: string }>;
    expect(content[0].type).toBe('text');

    const upstream = JSON.parse(content[0].text);
    expect(upstream.status).toBe(200);
    expect(upstream.data.seen_path).toBe('/pet/7?verbose=true');
  });

  it('reports an unknown tool through isError rather than a transport failure', async () => {
    const c = await connected();
    const result = await c.callTool({ name: 'nope', arguments: {} });

    expect(result.isError).toBe(true);
    const content = result.content as Array<{ type: string; text: string }>;
    expect(content[0].text).toContain('Tool nope not found');
  });

  it('answers ping', async () => {
    const c = await connected();
    await expect(c.ping()).resolves.toBeDefined();
  });

  it('serves several sequential calls on one connection', async () => {
    const c = await connected();
    for (let i = 0; i < 3; i++) {
      const { tools } = await c.listTools();
      expect(tools.length).toBeGreaterThan(0);
    }
  });

  it('serves several calls in flight at once on one connection', async () => {
    // A real client does not wait for one answer before sending the next; it
    // matches them by id. The Python concurrency suite drives that with raw
    // sockets, which cannot tell whether the SDK's own correlation still works.
    const c = await connected();
    const [tools, pong, call] = await Promise.all([
      c.listTools(),
      c.ping(),
      c.callTool({ name: 'getPet', arguments: { pathParameters: { petId: 3 } } }),
    ]);

    expect(tools.tools.length).toBeGreaterThan(0);
    expect(pong).toBeDefined();
    expect((call as { isError?: boolean }).isError).toBeFalsy();
  });

  it('can connect again after close()', async () => {
    const first = await connected();
    const before = (await first.listTools()).tools.length;
    await first.close();

    const second = await connected();
    expect((await second.listTools()).tools).toHaveLength(before);
  });
});
