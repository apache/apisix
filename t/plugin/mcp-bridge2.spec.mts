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
import { readFileSync } from 'node:fs';
import { unlink, writeFile } from 'node:fs/promises';

import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { SSEClientTransport } from '@modelcontextprotocol/sdk/client/sse.js';
import { resolve } from 'node:path';


const tools = JSON.parse(
  readFileSync(resolve(`./plugin/mcp/assets/bridge-list-tools.json`), 'utf-8'),
);
const sseEndpoint = new URL('http://localhost:1984/mcp/sse');

describe('mcp-bridge', () => {
  let client: Client;

  beforeEach(async () => {
    client = new Client({ name: 'apisix-e2e-test', version: '1.0.0' });
    try {
      await client.connect(new SSEClientTransport(sseEndpoint));
    } catch (error) {
      console.error('Connection error:', error);
      throw error;
    }
  });

  it('should list tools', () => {
    console.log('client not connected');
  });
});
